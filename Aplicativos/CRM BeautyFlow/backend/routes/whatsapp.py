import os
import re
import base64
import logging
import datetime
import requests
from flask import Blueprint, request, jsonify
from db.database import (
    get_db, get_settings, update_setting, create_notification,
    delete_integrations_by_type, is_type_integrated
)

logger = logging.getLogger(__name__)

whatsapp_bp = Blueprint('whatsapp', __name__)

DEFAULT_API_KEY = '218c0effefb845238a1ae3651c8ced5b'

DEFAULT_TEMPLATES = {
    'whatsapp_template_created': (
        "Olá, *{nome}*! 🌸\n\n"
        "Seu agendamento de *{servico}* foi confirmado com sucesso!\n"
        "📅 *Data:* {data}\n"
        "⏰ *Horário:* {horario}\n"
        "💰 *Valor:* R$ {valor}\n\n"
        "Esperamos por você no *{empresa}*! Caso precise reagendar, por favor nos avise."
    ),
    'whatsapp_template_reminder': (
        "Olá, *{nome}*! 💅 Passando para lembrar do seu horário agendado de *{servico}* amanhã ({data}) às *{horario}* no *{empresa}*.\n\n"
        "Qualquer imprevisto ou dúvida, por favor nos responda por aqui!"
    ),
    'whatsapp_template_cancelled': (
        "Olá, *{nome}*.\n\n"
        "Informamos que seu agendamento de *{servico}* marcado para *{data} às {horario}* foi cancelado.\n\n"
        "Ficamos à disposição para um novo agendamento quando desejar!"
    ),
    'whatsapp_template_return': (
        "Olá, *{nome}*! ✨ Sentimos sua falta por aqui no *{empresa}*! "
        "Que tal agendarmos uma manutenção para manter suas unhas lindas e impecáveis? Responda para escolhermos o melhor horário!"
    ),
    'whatsapp_template_thanks': (
        "Olá, *{nome}*! 💖 Muito obrigado pela sua visita ao *{empresa}* hoje! "
        "Foi um enorme prazer atender você. Esperamos vê-la novamente em breve!"
    ),
}


def render_whatsapp_template(template_text, context):
    if not template_text:
        return ''
    text = str(template_text)
    for k, v in context.items():
        text = text.replace(f"{{{k}}}", str(v or ''))
    return text


def _candidate_urls():
    env_url = (os.environ.get('WAHA_API_URL') or '').strip().rstrip('/')
    s = get_settings()
    custom_url = (s.get('waha_api_url') or '').strip().rstrip('/')
    candidates = []
    if custom_url:
        candidates.append(custom_url)
    if env_url and env_url not in candidates:
        candidates.append(env_url)
    for default in ['http://waha:3000', 'http://localhost:3000', 'http://127.0.0.1:3000']:
        if default not in candidates:
            candidates.append(default)
    return candidates


def get_docker_gateway():
    """Returns the default gateway IP of the current container (which points to Docker host)."""
    try:
        with open('/proc/net/route') as f:
            for line in f:
                fields = line.strip().split()
                if len(fields) >= 3 and fields[1] == '00000000':
                    import struct, socket
                    return socket.inet_ntoa(struct.pack('<L', int(fields[2], 16)))
    except Exception:
        pass
    return '172.23.0.1'


def resolve_url_for_docker(url: str) -> str:
    """If running inside a Docker container and the URL points to localhost or 127.0.0.1,
    replaces localhost with the Docker host gateway IP so the container (and WAHA) can reach host-bound services (like n8n)."""
    if not url:
        return url
    try:
        from urllib.parse import urlparse, urlunparse
        parsed = urlparse(url)
        hostname = (parsed.hostname or '').lower()
        if hostname in ('localhost', '127.0.0.1'):
            gateway = get_docker_gateway()
            if gateway:
                port_str = f":{parsed.port}" if parsed.port else ""
                auth = f"{parsed.username}:{parsed.password}@" if parsed.password else (f"{parsed.username}@" if parsed.username else "")
                new_netloc = f"{auth}{gateway}{port_str}"
                return urlunparse((parsed.scheme, new_netloc, parsed.path, parsed.params, parsed.query, parsed.fragment))
    except Exception:
        pass
    return url


def _get_api_key():
    s = get_settings()
    key = (s.get('waha_api_key') or '').strip()
    if key:
        return key
    env_key = (os.environ.get('WAHA_API_KEY') or '').strip()
    if env_key:
        return env_key
    return DEFAULT_API_KEY


def _get_headers():
    key = _get_api_key()
    return {'X-Api-Key': key} if key else {}


def get_working_waha_url():
    headers = _get_headers()
    for url in _candidate_urls():
        try:
            r = requests.get(f"{url}/ping", headers=headers, timeout=2.0)
            if r.status_code in (200, 401):
                return url
        except Exception:
            continue
    return None


def get_session_name(waha_url):
    s = get_settings()
    configured = (s.get('waha_session_name') or '').strip()
    if configured:
        return configured

    env_sess = (os.environ.get('WAHA_SESSION') or '').strip()
    if env_sess:
        return env_sess

    headers = _get_headers()
    try:
        r = requests.get(f"{waha_url}/api/sessions", headers=headers, timeout=3.0)
        if r.status_code == 200:
            sessions = r.json()
            if isinstance(sessions, list) and len(sessions) > 0:
                for s_item in sessions:
                    if s_item.get('status') == 'WORKING':
                        return s_item.get('name')
                return sessions[0].get('name')
    except Exception:
        pass

    return 'default'


def clean_phone_number(raw_phone):
    digits = re.sub(r'\D', '', str(raw_phone or ''))
    if not digits:
        return ''
    if digits.startswith('55') and len(digits) in (12, 13):
        return digits
    if len(digits) in (10, 11):
        return '55' + digits
    return digits


@whatsapp_bp.route('/status', methods=['GET'])
def get_status():
    s = get_settings()
    is_integrated = is_type_integrated('whatsapp') or is_type_integrated('waha') or (s.get('whatsapp_integrated') == 'true')
    waha_url = get_working_waha_url()
    if not waha_url:
        return jsonify({
            'installed': False,
            'is_integrated': is_integrated,
            'status': 'NOT_INSTALLED',
            'error': 'O WAHA (WhatsApp HTTP API) não foi instalado na plataforma. Ative a instalação do WAHA pelo instalador para utilizar o WhatsApp.',
            'waha_url': None,
            'me': None
        }), 200

    headers = _get_headers()
    try:
        r_ping = requests.get(f"{waha_url}/ping", headers=headers, timeout=3.0)
        if r_ping.status_code == 401:
            return jsonify({
                'installed': True,
                'is_integrated': is_integrated,
                'status': 'AUTH_REQUIRED',
                'error': 'Chave de API do WAHA não autorizada. Verifique a configuração de segurança.',
                'waha_url': waha_url,
                'me': None
            }), 200
    except Exception as e:
        return jsonify({
            'installed': False,
            'is_integrated': is_integrated,
            'status': 'NOT_INSTALLED',
            'error': 'O WAHA (WhatsApp HTTP API) não foi instalado na plataforma. Ative a instalação do WAHA pelo instalador para utilizar o WhatsApp.',
            'waha_url': None,
            'me': None
        }), 200

    session_name = get_session_name(waha_url)
    session_status = 'STOPPED'
    me_info = None

    try:
        r_sess = requests.get(f"{waha_url}/api/sessions/{session_name}", headers=headers, timeout=4.0)
        if r_sess.status_code == 200:
            sess_data = r_sess.json()
            session_status = sess_data.get('status', 'STOPPED')
            me_info = sess_data.get('me')
        elif r_sess.status_code == 404:
            r_start = requests.post(
                f"{waha_url}/api/sessions",
                json={'name': session_name, 'start': True},
                headers=headers,
                timeout=5.0
            )
            if r_start.status_code in (200, 201):
                session_status = 'STARTING'
            else:
                session_status = 'STOPPED'
    except Exception as e:
        logger.warning(f"Erro ao consultar sessao {session_name} no WAHA: {e}")

    s = get_settings()
    empresa = s.get('company_name') or s.get('studio_name') or 'BeautyFlow'
    is_integrated = is_type_integrated('whatsapp') or is_type_integrated('waha') or (s.get('whatsapp_integrated') == 'true')
    return jsonify({
        'installed': True,
        'is_integrated': is_integrated,
        'status': session_status,
        'session': session_name,
        'session_name': session_name,
        'waha_url': waha_url,
        'me': me_info,
        'error': None,
        'n8n_webhook_url': s.get('n8n_whatsapp_webhook_url', ''),
        'n8n_webhook_events': s.get('n8n_whatsapp_webhook_events', 'message,message.any'),
        'settings': {
            'notify_on_create': s.get('whatsapp_auto_notify_created', 'true') == 'true',
            'notify_on_cancel': s.get('whatsapp_auto_notify_cancelled', 'true') == 'true',
            'notify_on_reminder': s.get('whatsapp_auto_notify_reminder', 'true') == 'true',
            'notify_on_return': s.get('whatsapp_auto_notify_return', 'false') == 'true',
            'notify_on_thanks': s.get('whatsapp_auto_notify_thanks', 'false') == 'true',
            'auto_notify_created': s.get('whatsapp_auto_notify_created', 'true') == 'true',
            'auto_notify_reminder': s.get('whatsapp_auto_notify_reminder', 'true') == 'true',
            'auto_notify_cancelled': s.get('whatsapp_auto_notify_cancelled', 'true') == 'true',
            'auto_notify_return': s.get('whatsapp_auto_notify_return', 'false') == 'true',
            'auto_notify_thanks': s.get('whatsapp_auto_notify_thanks', 'false') == 'true',
            'reminder_timing': s.get('whatsapp_reminder_timing', '1_day'),
            'reminder_time': s.get('whatsapp_reminder_time', '09:00'),
            'return_interval_days': s.get('whatsapp_return_interval_days', '20'),
            'return_time': s.get('whatsapp_return_time', '10:00'),
            'thanks_delay': s.get('whatsapp_thanks_delay', 'immediate'),
            'waha_api_url': s.get('waha_api_url', ''),
            'waha_api_key': s.get('waha_api_key', ''),
            'waha_session_name': s.get('waha_session_name', ''),
            'country_code': s.get('whatsapp_country_code', '55'),
            'company_name': empresa,
            'template_created': s.get('whatsapp_template_created') or DEFAULT_TEMPLATES['whatsapp_template_created'],
            'template_reminder': s.get('whatsapp_template_reminder') or DEFAULT_TEMPLATES['whatsapp_template_reminder'],
            'template_cancelled': s.get('whatsapp_template_cancelled') or DEFAULT_TEMPLATES['whatsapp_template_cancelled'],
            'template_return': s.get('whatsapp_template_return') or DEFAULT_TEMPLATES['whatsapp_template_return'],
            'template_thanks': s.get('whatsapp_template_thanks') or DEFAULT_TEMPLATES['whatsapp_template_thanks'],
        }
    })


@whatsapp_bp.route('/qr', methods=['GET'])
def get_qr():
    waha_url = get_working_waha_url()
    if not waha_url:
        return jsonify({
            'installed': False,
            'error': 'O WAHA (WhatsApp HTTP API) não foi instalado na plataforma. Ative a instalação do WAHA pelo instalador para utilizar o WhatsApp.'
        }), 503

    headers = _get_headers()
    session_name = get_session_name(waha_url)
    force_refresh = request.args.get('refresh') in ('true', '1', 'yes')

    if force_refresh:
        try:
            requests.post(f"{waha_url}/api/sessions/{session_name}/restart", headers=headers, timeout=6.0)
            import time
            time.sleep(1.2)
        except Exception as e:
            logger.warning(f"Erro ao forçar refresh do QR: {e}")

    try:
        r_sess = requests.get(f"{waha_url}/api/sessions/{session_name}", headers=headers, timeout=3.0)
        if r_sess.status_code == 404:
            requests.post(
                f"{waha_url}/api/sessions",
                json={'name': session_name, 'start': True},
                headers=headers,
                timeout=4.0
            )
        elif r_sess.status_code == 200:
            sess_data = r_sess.json()
            curr_status = sess_data.get('status')
            if curr_status == 'WORKING':
                return jsonify({
                    'status': 'WORKING',
                    'message': 'WhatsApp já está conectado.',
                    'me': sess_data.get('me'),
                    'session': session_name
                })
            elif curr_status == 'STOPPED':
                requests.post(f"{waha_url}/api/sessions/{session_name}/start", headers=headers, timeout=4.0)
    except Exception:
        pass

    try:
        r_qr = requests.get(f"{waha_url}/api/{session_name}/auth/qr", headers=headers, timeout=5.0)
        if r_qr.status_code == 200 and len(r_qr.content) > 100:
            b64_qr = base64.b64encode(r_qr.content).decode('ascii')
            content_type = r_qr.headers.get('content-type', 'image/png')
            data_url = f"data:{content_type};base64,{b64_qr}"
            return jsonify({
                'status': 'SCAN_QR_CODE',
                'qr': data_url,
                'qr_image': data_url,
                'session': session_name,
                'expires_in': 35
            })
    except Exception as e:
        logger.warning(f"Erro ao buscar QR Code no WAHA: {e}")

    return jsonify({
        'status': 'STARTING',
        'qr_image': None,
        'message': 'Aguardando o WAHA gerar o QR Code...',
        'session': session_name
    })


@whatsapp_bp.route('/refresh-qr', methods=['POST'])
def refresh_qr_code():
    waha_url = get_working_waha_url()
    if not waha_url:
        return jsonify({'error': 'WAHA não instalado na plataforma.'}), 503

    headers = _get_headers()
    session_name = get_session_name(waha_url)

    try:
        r_sess = requests.get(f"{waha_url}/api/sessions/{session_name}", headers=headers, timeout=3.0)
        if r_sess.status_code == 200 and r_sess.json().get('status') == 'WORKING':
            return jsonify({
                'status': 'WORKING',
                'message': 'WhatsApp já está conectado.',
                'session': session_name
            })
    except Exception:
        pass

    try:
        requests.post(f"{waha_url}/api/sessions/{session_name}/restart", headers=headers, timeout=6.0)
    except Exception:
        try:
            requests.post(f"{waha_url}/api/sessions/{session_name}/start", headers=headers, timeout=4.0)
        except Exception:
            pass

    import time
    for _ in range(4):
        time.sleep(1.2)
        try:
            r_qr = requests.get(f"{waha_url}/api/{session_name}/auth/qr", headers=headers, timeout=5.0)
            if r_qr.status_code == 200 and len(r_qr.content) > 100:
                b64_qr = base64.b64encode(r_qr.content).decode('ascii')
                content_type = r_qr.headers.get('content-type', 'image/png')
                data_url = f"data:{content_type};base64,{b64_qr}"
                return jsonify({
                    'status': 'SCAN_QR_CODE',
                    'qr': data_url,
                    'qr_image': data_url,
                    'session': session_name,
                    'expires_in': 35
                })
        except Exception:
            continue

    return jsonify({
        'status': 'STARTING',
        'qr': None,
        'message': 'Sessão reiniciada. O QR Code está sendo processado...',
        'session': session_name
    })


@whatsapp_bp.route('/screenshot', methods=['GET'])
def get_screenshot():
    waha_url = get_working_waha_url()
    if not waha_url:
        return jsonify({
            'success': False,
            'error': 'WAHA não está instalado ou não está em execução na porta 3000.'
        }), 503

    headers = _get_headers()
    session_name = get_session_name(waha_url)

    try:
        r = requests.get(f"{waha_url}/api/screenshot?session={session_name}", headers=headers, timeout=10.0)
        if r.status_code == 200 and len(r.content) > 100:
            b64_img = base64.b64encode(r.content).decode('ascii')
            content_type = r.headers.get('content-type', 'image/jpeg')
            data_url = f"data:{content_type};base64,{b64_img}"
            import datetime
            now_str = datetime.datetime.now().strftime('%d/%m/%Y às %H:%M:%S')
            return jsonify({
                'success': True,
                'screenshot': data_url,
                'session': session_name,
                'timestamp': now_str
            })
        return jsonify({
            'success': False,
            'error': f'WAHA retornou status {r.status_code}: {r.text[:200]}'
        }), 502
    except Exception as e:
        logger.warning(f"Erro ao capturar tela do WAHA: {e}")
        return jsonify({'success': False, 'error': f'Erro ao obter captura de tela: {str(e)}'}), 500


@whatsapp_bp.route('/start', methods=['POST'])
def start_session():
    waha_url = get_working_waha_url()
    if not waha_url:
        return jsonify({'error': 'WAHA não instalado na plataforma.'}), 503

    headers = _get_headers()
    session_name = get_session_name(waha_url)
    try:
        r = requests.post(f"{waha_url}/api/sessions/{session_name}/start", headers=headers, timeout=5.0)
        if r.status_code == 404:
            r = requests.post(
                f"{waha_url}/api/sessions",
                json={'name': session_name, 'start': True},
                headers=headers,
                timeout=5.0
            )
        return jsonify({'success': True, 'status': 'ok', 'message': 'Sessão iniciada.'})
    except Exception as e:
        return jsonify({'success': False, 'error': f'Erro ao iniciar sessão: {str(e)}'}), 500


@whatsapp_bp.route('/logout', methods=['POST'])
def logout_session():
    waha_url = get_working_waha_url()
    if not waha_url:
        return jsonify({'success': False, 'error': 'WAHA não instalado na plataforma.'}), 503

    headers = _get_headers()
    session_name = get_session_name(waha_url)
    try:
        requests.post(f"{waha_url}/api/sessions/{session_name}/logout", headers=headers, timeout=5.0)
        return jsonify({'success': True, 'status': 'ok', 'message': 'WhatsApp desconectado.'})
    except Exception as e:
        return jsonify({'success': False, 'error': f'Erro ao desconectar: {str(e)}'}), 500


@whatsapp_bp.route('/integration', methods=['DELETE'])
@whatsapp_bp.route('/disconnect', methods=['POST', 'DELETE'])
def remove_integration():
    """Removes the WhatsApp integration completely: logs out WAHA, clears webhooks, deletes DB row, and resets settings."""
    waha_url = get_working_waha_url()
    if waha_url:
        headers = _get_headers()
        session_name = get_session_name(waha_url)
        try:
            requests.post(f"{waha_url}/api/sessions/{session_name}/logout", headers=headers, timeout=5.0)
        except Exception as e:
            logger.warning(f"Erro ao deslogar sessão {session_name} no WAHA: {e}")
        try:
            requests.put(f"{waha_url}/api/sessions/{session_name}", json={'config': {'webhooks': []}}, headers=headers, timeout=5.0)
        except Exception as e:
            logger.warning(f"Erro ao resetar webhooks no WAHA: {e}")

    # Remove from integrations table
    delete_integrations_by_type('whatsapp')
    delete_integrations_by_type('waha')

    # Reset integration settings
    update_setting('whatsapp_integrated', 'false')
    update_setting('whatsapp_auto_notify_created', 'false')
    update_setting('whatsapp_auto_notify_cancelled', 'false')
    update_setting('whatsapp_auto_notify_reminder', 'false')
    update_setting('n8n_whatsapp_webhook_url', '')

    return jsonify({
        'success': True,
        'status': 'ok',
        'message': 'Integração do WhatsApp removida com sucesso.'
    }), 200


@whatsapp_bp.route('/webhook/config', methods=['GET', 'POST'])
def webhook_config():
    """Gets or sets the n8n webhook URL and synchronizes it with WAHA session configuration."""
    if request.method == 'POST':
        data = request.get_json(silent=True) or {}
        url = (data.get('url') or '').strip()
        events = data.get('events') or ['message', 'message.any']
        if isinstance(events, str):
            events = [e.strip() for e in events.split(',') if e.strip()]

        if url and not (url.startswith('http://') or url.startswith('https://')):
            return jsonify({'error': 'A URL do webhook deve começar com http:// ou https://'}), 400

        update_setting('n8n_whatsapp_webhook_url', url)
        update_setting('n8n_whatsapp_webhook_events', ','.join(events))

        waha_url = get_working_waha_url()
        waha_synced = False
        if waha_url:
            session_name = get_session_name(waha_url)
            headers = _get_headers()
            webhooks_config = []
            if url:
                waha_target_url = resolve_url_for_docker(url)
                webhooks_config.append({
                    'url': waha_target_url,
                    'events': events
                })
            try:
                r_waha = requests.put(
                    f"{waha_url}/api/sessions/{session_name}",
                    json={'config': {'webhooks': webhooks_config}},
                    headers=headers,
                    timeout=8.0
                )
                waha_synced = r_waha.status_code in (200, 201)
            except Exception as e:
                logger.warning(f"Falha ao sincronizar webhook com WAHA: {e}")

        return jsonify({
            'status': 'ok',
            'message': 'Webhook do n8n salvo e sincronizado com o WhatsApp (WAHA)!' if url else 'Configuração de webhook limpa.',
            'url': url,
            'events': events,
            'waha_synced': waha_synced
        })

    s = get_settings()
    events_str = s.get('n8n_whatsapp_webhook_events', 'message,message.any')
    events = [e.strip() for e in events_str.split(',') if e.strip()]
    return jsonify({
        'url': s.get('n8n_whatsapp_webhook_url', ''),
        'events': events
    })


@whatsapp_bp.route('/webhook/test', methods=['POST'])
def test_webhook():
    """Sends a mock WAHA message webhook payload to the configured n8n URL to verify connectivity."""
    import time
    data = request.get_json(silent=True) or {}
    url = (data.get('url') or '').strip()
    if not url:
        s = get_settings()
        url = (s.get('n8n_whatsapp_webhook_url') or '').strip()

    if not url:
        return jsonify({'error': 'Nenhuma URL de Webhook informada ou salva para teste.'}), 400

    if not (url.startswith('http://') or url.startswith('https://')):
        return jsonify({'error': 'URL inválida. Deve iniciar com http:// ou https://'}), 400

    waha_url = get_working_waha_url()
    session_name = get_session_name(waha_url) if waha_url else 'beautyflow'
    s = get_settings()
    empresa = s.get('company_name') or s.get('studio_name') or 'BeautyFlow'

    test_payload = {
        'event': 'message',
        'session': session_name,
        'metadata': {
            'source': 'beautyflow_crm',
            'flow': 'n8n_incoming_test'
        },
        'payload': {
            'id': f"beautyflow_test_{int(time.time())}",
            'timestamp': int(time.time()),
            'from': '5511999999999@c.us',
            'to': '5511988888888@c.us',
            'fromMe': False,
            'body': f"Olá! Este é um teste de escuta enviado pelo {empresa} para validar seu nó Webhook no n8n. 🚀",
            'hasMedia': False,
            'ack': 1,
            'ackName': 'DEVICE',
            '_data': {
                'notifyName': 'Cliente Exemplo n8n',
                'type': 'chat'
            }
        }
    }

    target_url = resolve_url_for_docker(url)
    resolved_info = ""
    if target_url != url:
        resolved_info = f" (convertido de localhost para {target_url.split('/')[2]} no Docker)"

    try:
        r = requests.post(
            target_url,
            json=test_payload,
            headers={'Content-Type': 'application/json', 'User-Agent': 'BeautyFlow-WAHA-Webhook/1.0'},
            timeout=8.0
        )
        if r.status_code == 404:
            if 'webhook-test' in url:
                return jsonify({
                    'status': 'error',
                    'error': 'O n8n retornou 404 (Webhook de teste não ativo). No n8n, clique em "Test this trigger" ou "Execute step" no nó do webhook antes de clicar em testar aqui.',
                    'response': r.text[:300]
                }), 404
            else:
                return jsonify({
                    'status': 'error',
                    'error': 'O n8n retornou 404 (Webhook não registrado). Ative o workflow no n8n (chave "Active" no topo) para que a Production URL responda.',
                    'response': r.text[:300]
                }), 404

        return jsonify({
            'status': 'ok',
            'http_status': r.status_code,
            'message': f'Disparo de teste recebido pelo n8n com status HTTP {r.status_code}!{resolved_info}',
            'response': r.text[:300]
        })
    except requests.exceptions.Timeout:
        return jsonify({'error': f'Tempo limite de 8s excedido para {target_url}. Verifique se o n8n está rodando e acessível.'}), 504
    except requests.exceptions.ConnectionError:
        return jsonify({'error': f'Não foi possível conectar à URL do n8n ({target_url}). Verifique se o serviço do n8n está ativo e a porta 5678 aberta.'}), 502
    except Exception as e:
        return jsonify({'error': f'Erro ao disparar teste para o n8n: {str(e)}'}), 500


@whatsapp_bp.route('/send-notification', methods=['POST'])
def send_notification():
    waha_url = get_working_waha_url()
    if not waha_url:
        return jsonify({
            'error': 'O WAHA não foi instalado na plataforma. Ative a instalação do WAHA pelo instalador para utilizar o WhatsApp.'
        }), 503

    data = request.get_json(silent=True) or {}
    raw_phone = (data.get('phone') or '').strip()
    message = (data.get('message') or '').strip()
    client_name = (data.get('client_name') or '').strip()

    if not raw_phone:
        return jsonify({'error': 'Telefone do cliente é obrigatório.'}), 400
    if not message:
        return jsonify({'error': 'Mensagem de notificação é obrigatória.'}), 400

    clean_phone = clean_phone_number(raw_phone)
    if len(clean_phone) < 10:
        return jsonify({'error': f'Número de telefone inválido: {raw_phone}'}), 400

    headers = _get_headers()
    session_name = get_session_name(waha_url)

    try:
        r_sess = requests.get(f"{waha_url}/api/sessions/{session_name}", headers=headers, timeout=3.0)
        if r_sess.status_code == 200:
            sess_status = r_sess.json().get('status')
            if sess_status != 'WORKING':
                return jsonify({
                    'error': f'O WhatsApp não está conectado (status atual: {sess_status}). Conecte o WhatsApp lendo o QR Code nas Integrações antes de enviar notificações.'
                }), 400
    except Exception:
        pass

    chat_id = f"{clean_phone}@c.us"
    payload = {
        'session': session_name,
        'chatId': chat_id,
        'text': message
    }

    try:
        r = requests.post(f"{waha_url}/api/sendText", json=payload, headers=headers, timeout=10.0)
        if r.status_code in (200, 201):
            try:
                create_notification(
                    'whatsapp_notification',
                    'Notificação WhatsApp Enviada',
                    f"Mensagem enviada para {client_name or clean_phone} ({clean_phone})",
                    related_id=data.get('appointment_id'),
                    related_type='appointment' if data.get('appointment_id') else 'client'
                )
            except Exception:
                pass
            return jsonify({
                'success': True,
                'status': 'ok',
                'message': 'Notificação enviada com sucesso para o WhatsApp!',
                'to': clean_phone,
                'chatId': chat_id
            })
        else:
            return jsonify({
                'success': False,
                'error': f'Erro ao enviar mensagem via WAHA ({r.status_code}): {r.text[:300]}'
            }), 502
    except requests.exceptions.Timeout:
        return jsonify({'success': False, 'error': 'Tempo limite ao comunicar com o WAHA.'}), 504
    except Exception as e:
        return jsonify({'success': False, 'error': f'Falha no envio via WhatsApp: {str(e)}'}), 500


@whatsapp_bp.route('/test', methods=['POST'])
def test_whatsapp():
    waha_url = get_working_waha_url()
    if not waha_url:
        return jsonify({
            'success': False,
            'error': 'O WAHA não foi instalado na plataforma. Ative a instalação do WAHA pelo instalador para utilizar o WhatsApp.'
        }), 503

    data = request.get_json(silent=True) or {}
    phone = (data.get('phone') or '').strip()
    if not phone:
        s = get_settings()
        phone = (s.get('company_phone') or s.get('profile_phone') or '').strip()
    if not phone:
        return jsonify({'success': False, 'error': 'Informe um número de telefone para o teste.'}), 400

    clean_phone = clean_phone_number(phone)
    session_name = get_session_name(waha_url)
    headers = _get_headers()

    test_msg = (
        "✨ *BeautyFlow CRM — Notificação de Teste*\n\n"
        "Seu WhatsApp foi integrado com sucesso à plataforma!\n"
        "Esta integração é utilizada para envio automático de lembretes e notificações aos seus clientes."
    )

    payload = {
        'session': session_name,
        'chatId': f"{clean_phone}@c.us",
        'text': test_msg
    }

    try:
        r = requests.post(f"{waha_url}/api/sendText", json=payload, headers=headers, timeout=10.0)
        if r.status_code in (200, 201):
            return jsonify({
                'success': True,
                'status': 'ok',
                'message': f'Mensagem de teste enviada com sucesso para {clean_phone}!',
                'to': clean_phone
            })
        return jsonify({
            'success': False,
            'error': f'WAHA retornou erro ({r.status_code}): {r.text[:300]}'
        }), 502
    except Exception as e:
        return jsonify({'success': False, 'error': f'Falha ao enviar mensagem de teste: {str(e)}'}), 500


@whatsapp_bp.route('/settings', methods=['GET', 'POST'])
def manage_settings():
    if request.method == 'POST':
        data = request.get_json(silent=True) or {}
        alias_map = {
            'notify_on_create': 'whatsapp_auto_notify_created',
            'notify_on_reminder': 'whatsapp_auto_notify_reminder',
            'notify_on_cancel': 'whatsapp_auto_notify_cancelled',
            'notify_on_return': 'whatsapp_auto_notify_return',
            'notify_on_thanks': 'whatsapp_auto_notify_thanks',
            'reminder_timing': 'whatsapp_reminder_timing',
            'reminder_time': 'whatsapp_reminder_time',
            'return_interval_days': 'whatsapp_return_interval_days',
            'return_time': 'whatsapp_return_time',
            'thanks_delay': 'whatsapp_thanks_delay',
            'template_created': 'whatsapp_template_created',
            'template_reminder': 'whatsapp_template_reminder',
            'template_cancelled': 'whatsapp_template_cancelled',
            'template_return': 'whatsapp_template_return',
            'template_thanks': 'whatsapp_template_thanks',
            'country_code': 'whatsapp_country_code'
        }
        for k, target in alias_map.items():
            if k in data and target not in data:
                data[target] = data[k]

        allowed_keys = [
            'whatsapp_auto_notify_created',
            'whatsapp_auto_notify_reminder',
            'whatsapp_auto_notify_cancelled',
            'whatsapp_auto_notify_return',
            'whatsapp_auto_notify_thanks',
            'whatsapp_reminder_timing',
            'whatsapp_reminder_time',
            'whatsapp_return_interval_days',
            'whatsapp_return_time',
            'whatsapp_thanks_delay',
            'whatsapp_template_created',
            'whatsapp_template_reminder',
            'whatsapp_template_cancelled',
            'whatsapp_template_return',
            'whatsapp_template_thanks',
            'waha_api_key',
            'waha_session_name',
            'waha_api_url',
            'whatsapp_country_code'
        ]
        for key in allowed_keys:
            if key in data:
                val = data[key]
                if isinstance(val, bool):
                    val = 'true' if val else 'false'
                update_setting(key, str(val))
        return jsonify({'status': 'ok', 'message': 'Configurações de WhatsApp salvas com sucesso.'})

    s = get_settings()
    empresa = s.get('company_name') or s.get('studio_name') or 'BeautyFlow'
    return jsonify({
        'auto_notify_created': s.get('whatsapp_auto_notify_created', 'true') == 'true',
        'auto_notify_reminder': s.get('whatsapp_auto_notify_reminder', 'true') == 'true',
        'auto_notify_cancelled': s.get('whatsapp_auto_notify_cancelled', 'true') == 'true',
        'auto_notify_return': s.get('whatsapp_auto_notify_return', 'false') == 'true',
        'auto_notify_thanks': s.get('whatsapp_auto_notify_thanks', 'false') == 'true',
        'notify_on_create': s.get('whatsapp_auto_notify_created', 'true') == 'true',
        'notify_on_reminder': s.get('whatsapp_auto_notify_reminder', 'true') == 'true',
        'notify_on_cancel': s.get('whatsapp_auto_notify_cancelled', 'true') == 'true',
        'notify_on_return': s.get('whatsapp_auto_notify_return', 'false') == 'true',
        'notify_on_thanks': s.get('whatsapp_auto_notify_thanks', 'false') == 'true',
        'reminder_timing': s.get('whatsapp_reminder_timing', '1_day'),
        'reminder_time': s.get('whatsapp_reminder_time', '09:00'),
        'return_interval_days': s.get('whatsapp_return_interval_days', '20'),
        'return_time': s.get('whatsapp_return_time', '10:00'),
        'thanks_delay': s.get('whatsapp_thanks_delay', 'immediate'),
        'waha_api_key': s.get('waha_api_key', ''),
        'waha_session_name': s.get('waha_session_name', ''),
        'waha_api_url': s.get('waha_api_url', ''),
        'country_code': s.get('whatsapp_country_code', '55'),
        'company_name': empresa,
        'template_created': s.get('whatsapp_template_created') or DEFAULT_TEMPLATES['whatsapp_template_created'],
        'template_reminder': s.get('whatsapp_template_reminder') or DEFAULT_TEMPLATES['whatsapp_template_reminder'],
        'template_cancelled': s.get('whatsapp_template_cancelled') or DEFAULT_TEMPLATES['whatsapp_template_cancelled'],
        'template_return': s.get('whatsapp_template_return') or DEFAULT_TEMPLATES['whatsapp_template_return'],
        'template_thanks': s.get('whatsapp_template_thanks') or DEFAULT_TEMPLATES['whatsapp_template_thanks'],
    })


def process_pending_whatsapp_reminders():
    """
    Verifica agendamentos que devem receber lembrete via WhatsApp de acordo com
    whatsapp_reminder_timing ('1_day', '2_days', '3_days', 'same_day', '2_hours', '4_hours', '6_hours')
    e whatsapp_reminder_time ('09:00').
    """
    try:
        s = get_settings()
        if s.get('whatsapp_auto_notify_reminder', 'true') != 'true':
            return {'sent': 0, 'status': 'disabled', 'message': 'Lembretes automáticos desativados'}

        waha_url = get_working_waha_url()
        if not waha_url:
            return {'sent': 0, 'status': 'offline', 'message': 'Serviço do WhatsApp offline'}

        timing = s.get('whatsapp_reminder_timing', '1_day')
        now = datetime.datetime.now()

        target_dates = []
        is_hour_based = timing in ('2_hours', '4_hours', '6_hours')

        if timing == '1_day':
            target_dates.append((now + datetime.timedelta(days=1)).strftime('%Y-%m-%d'))
        elif timing == '2_days':
            target_dates.append((now + datetime.timedelta(days=2)).strftime('%Y-%m-%d'))
        elif timing == '3_days':
            target_dates.append((now + datetime.timedelta(days=3)).strftime('%Y-%m-%d'))
        elif timing == 'same_day' or is_hour_based:
            target_dates.append(now.strftime('%Y-%m-%d'))

        db = get_db()
        sent_count = 0

        for t_date in target_dates:
            res = db.table('appointments').select('*, clients(name, phone)').eq('appointment_date', t_date).execute()
            appts = res.data or []

            for a in appts:
                if a.get('status') in ('cancelled', 'completed'):
                    continue

                appt_id = a.get('id')
                # Evita duplicidade usando tabela de notificações
                try:
                    already = db.table('notifications').select('id').eq('type', 'whatsapp_reminder').eq('related_id', appt_id).execute()
                    if already.data and len(already.data) > 0:
                        continue
                except Exception:
                    pass

                if is_hour_based:
                    appt_time_str = a.get('appointment_time') or '00:00'
                    try:
                        appt_dt = datetime.datetime.strptime(f"{t_date} {appt_time_str[:5]}", '%Y-%m-%d %H:%M')
                        diff_minutes = (appt_dt - now).total_seconds() / 60
                        if timing == '2_hours' and not (60 <= diff_minutes <= 150):
                            continue
                        elif timing == '4_hours' and not (180 <= diff_minutes <= 270):
                            continue
                        elif timing == '6_hours' and not (300 <= diff_minutes <= 390):
                            continue
                    except Exception:
                        continue

                phone = a.get('client_phone') or (a.get('clients') and a.get('clients').get('phone'))
                if not phone:
                    continue

                client_name = a.get('client_name') or (a.get('clients') and a.get('clients').get('name')) or 'Cliente'
                first_name = client_name.split()[0]
                service = a.get('service') or 'Atendimento'
                parts = t_date.split('-')
                date_fmt = f"{parts[2]}/{parts[1]}/{parts[0]}" if len(parts) == 3 else t_date
                time_str = (a.get('appointment_time') or '')[:5]
                price_val = f"{float(a.get('price', 0)):.2f}".replace('.', ',')
                empresa = s.get('company_name') or s.get('studio_name') or 'BeautyFlow'

                ctx = {
                    'nome': client_name,
                    'primeiro_nome': first_name,
                    'servico': service,
                    'data': date_fmt,
                    'horario': time_str,
                    'valor': price_val,
                    'empresa': empresa,
                }
                tmpl = s.get('whatsapp_template_reminder') or DEFAULT_TEMPLATES['whatsapp_template_reminder']
                msg = render_whatsapp_template(tmpl, ctx)

                send_whatsapp_async(phone, msg, client_name=client_name, appointment_id=appt_id)

                create_notification(
                    'whatsapp_reminder',
                    'Lembrete WhatsApp Enviado',
                    f"Lembrete automático enviado para {client_name} ({date_fmt} às {time_str})",
                    related_id=appt_id,
                    related_type='appointment'
                )
                sent_count += 1

        return {'sent': sent_count, 'status': 'ok'}
    except Exception as e:
        logger.warning(f"Erro ao processar lembretes WhatsApp: {e}")
        return {'sent': 0, 'error': str(e)}


@whatsapp_bp.route('/send-pending-reminders', methods=['POST'])
def trigger_pending_reminders():
    res = process_pending_whatsapp_reminders()
    return jsonify(res)


def send_whatsapp_async(phone, message, client_name='', appointment_id=None):
    import threading
    def _run():
        waha_url = get_working_waha_url()
        if not waha_url:
            return
        clean_phone = clean_phone_number(phone)
        if not clean_phone or len(clean_phone) < 10:
            return
        session_name = get_session_name(waha_url)
        headers = _get_headers()
        try:
            r_sess = requests.get(f"{waha_url}/api/sessions/{session_name}", headers=headers, timeout=2.0)
            if r_sess.status_code != 200 or r_sess.json().get('status') != 'WORKING':
                return
            payload = {
                'session': session_name,
                'chatId': f"{clean_phone}@c.us",
                'text': message
            }
            requests.post(f"{waha_url}/api/sendText", json=payload, headers=headers, timeout=8.0)
            create_notification(
                'whatsapp_notification',
                'Notificação WhatsApp Enviada',
                f"Mensagem enviada para {client_name or clean_phone}",
                related_id=appointment_id,
                related_type='appointment' if appointment_id else 'client'
            )
        except Exception as e:
            logger.warning(f"Falha no envio automatico de WhatsApp para {phone}: {e}")

    threading.Thread(target=_run, daemon=True).start()


def start_whatsapp_reminder_scheduler():
    import threading
    import time
    def _scheduler_loop():
        time.sleep(10)
        last_minute = None
        while True:
            try:
                now = datetime.datetime.now()
                current_min = now.strftime('%Y-%m-%d %H:%M')
                if current_min != last_minute:
                    last_minute = current_min
                    s = get_settings()
                    timing = s.get('whatsapp_reminder_timing', '1_day')
                    pref_time = s.get('whatsapp_reminder_time', '09:00')
                    now_time = now.strftime('%H:%M')

                    if timing in ('2_hours', '4_hours', '6_hours'):
                        if now.minute % 10 == 0:
                            process_pending_whatsapp_reminders()
                    elif now_time == pref_time:
                        process_pending_whatsapp_reminders()
            except Exception:
                pass
            time.sleep(25)

    t = threading.Thread(target=_scheduler_loop, daemon=True, name="WhatsAppReminderScheduler")
    t.start()


start_whatsapp_reminder_scheduler()

