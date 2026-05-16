import os
import datetime
import requests
from flask import Flask, jsonify, send_from_directory, request
from flask_cors import CORS
from db.database import get_db, get_settings, update_setting, get_stats
from routes.clients import clients_bp
from routes.appointments import appointments_bp
from routes.services import services_bp
from routes.users import users_bp

STATIC_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'src')

app = Flask(__name__, static_folder=None)
CORS(app)

app.register_blueprint(clients_bp, url_prefix='/api/clients')
app.register_blueprint(appointments_bp, url_prefix='/api/appointments')
app.register_blueprint(services_bp, url_prefix='/api/services')
app.register_blueprint(users_bp, url_prefix='/api/users')


# ─── Helper: obtém a URL do webhook n8n ────────────────────────────────────
# Prioridade: 1. settings no banco, 2. variável de ambiente, 3. fallback fixo
_N8N_FALLBACK = 'https://mirianfiorini.app.n8n.cloud/webhook/calendar-webhook'

def _n8n_webhook_url():
    try:
        s = get_settings()
        url = s.get('n8n_webhook_url', '').strip()
        if url:
            return url
    except Exception:
        pass
    return os.environ.get('N8N_WEBHOOK_URL', _N8N_FALLBACK)


# ─── Helper: envia payload para o n8n (sem lançar exceções) ─────────────────
def _fire_n8n_webhook(payload):
    url = _n8n_webhook_url()
    if not url:
        return
    try:
        requests.post(url, json=payload, timeout=8)
    except Exception:
        pass


# ══════════════════════════════════════════════════════════════════════════════
# Endpoints de configuração do n8n
# ══════════════════════════════════════════════════════════════════════════════

@ app.route('/api/n8n/config', methods=['GET', 'PUT'])
def n8n_config():
    if request.method == 'PUT':
        data = request.get_json()
        url = (data.get('webhook_url') or '').strip()
        update_setting('n8n_webhook_url', url)
        return jsonify({'status': 'ok', 'webhook_url': url})

    url = _n8n_webhook_url()
    return jsonify({'webhook_url': url})


@ app.route('/api/n8n/test', methods=['POST'])
def n8n_test():
    data = request.get_json(force=True) or {}
    url = (data.get('webhook_url') or '').strip() or _n8n_webhook_url()
    if not url:
        return jsonify({'error': 'Nenhuma URL de webhook configurada.'}), 400

    payload = {
        'action': 'test',
        'appointment_id': 0,
        'client_name': 'Teste BeautyFlow',
        'client_phone': '(11) 99999-0000',
        'service': 'Teste de Integração',
        'price': 0,
        'status': 'test',
        'start_datetime': datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%S-03:00'),
        'end_datetime': (datetime.datetime.now() + datetime.timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%S-03:00'),
        'google_event_id': '',
    }
    try:
        r = requests.post(url, json=payload, timeout=10)
        r.raise_for_status()
        return jsonify({
            'status': 'ok',
            'message': 'Webhook enviado com sucesso!',
            'n8n_status': r.status_code,
            'n8n_response': r.text[:500],
        })
    except requests.exceptions.Timeout:
        return jsonify({'error': 'Timeout — n8n não respondeu em 10 segundos.'}), 504
    except requests.exceptions.ConnectionError:
        return jsonify({'error': 'Conexão recusada — verifique a URL do webhook.'}), 502
    except requests.exceptions.HTTPError as e:
        return jsonify({'error': f'n8n retornou erro HTTP {e}'}), 502
    except Exception as e:
        return jsonify({'error': f'Erro inesperado: {str(e)}'}), 500


# ══════════════════════════════════════════════════════════════════════════════
# Endpoint de sincronização (usado internamente pelas rotas de agendamento)
# ══════════════════════════════════════════════════════════════════════════════

@ app.route('/api/n8n/sync-calendar', methods=['POST'])
def n8n_sync_calendar():
    data = request.get_json(force=True)

    required_fields = ['action', 'appointment_id', 'appointment_date', 'appointment_time']
    missing = [f for f in required_fields if f not in data]
    if missing:
        return jsonify({'error': f'Campos obrigatórios ausentes: {", ".join(missing)}'}), 400

    action = data.get('action', 'create')

    if action == 'delete' and not data.get('google_event_id'):
        return jsonify({'error': 'google_event_id é obrigatório para action=delete'}), 400

    try:
        appt_date = data['appointment_date']
        appt_time = data['appointment_time']
        duration  = int(data.get('duration_minutes', 60))
        start_dt = datetime.datetime.strptime(f"{appt_date} {appt_time}", "%Y-%m-%d %H:%M")
        end_dt = start_dt + datetime.timedelta(minutes=duration)
        tz_suffix = "-03:00"
        start_iso = start_dt.strftime("%Y-%m-%dT%H:%M:%S") + tz_suffix
        end_iso   = end_dt.strftime("%Y-%m-%dT%H:%M:%S") + tz_suffix
    except (ValueError, KeyError) as e:
        return jsonify({'error': f'Formato de data/hora inválido: {str(e)}'}), 400

    payload = {
        'action':           action,
        'appointment_id':   data.get('appointment_id'),
        'client_name':      data.get('client_name', 'Cliente'),
        'client_phone':     data.get('client_phone', ''),
        'service':          data.get('service', 'Serviço'),
        'price':            data.get('price', 0),
        'status':           data.get('status', 'pending'),
        'start_datetime':   start_iso,
        'end_datetime':     end_iso,
        'google_event_id':  data.get('google_event_id', ''),
    }

    url = _n8n_webhook_url()
    try:
        n8n_response = requests.post(url, json=payload, timeout=8)
        n8n_response.raise_for_status()
        return jsonify({
            'status': 'ok',
            'message': 'Sincronização enviada ao n8n com sucesso',
            'n8n_status': n8n_response.status_code,
            'payload_enviado': payload
        }), 200
    except requests.exceptions.Timeout:
        return jsonify({'error': 'Timeout ao conectar com o n8n.'}), 504
    except requests.exceptions.ConnectionError:
        return jsonify({'error': 'Não foi possível conectar ao n8n. Verifique a URL do webhook.'}), 502
    except requests.exceptions.HTTPError as e:
        return jsonify({'error': f'n8n retornou erro: {str(e)}'}), 502
    except Exception as e:
        return jsonify({'error': f'Erro inesperado: {str(e)}'}), 500


@ app.route('/api/n8n/status', methods=['GET'])
def n8n_status():
    url = _n8n_webhook_url()
    try:
        resp = requests.get(url, timeout=5)
        online = True
        http_code = resp.status_code
    except Exception:
        online = False
        http_code = None
    return jsonify({
        'n8n_webhook_url': url,
        'n8n_reachable': online,
        'n8n_http_code': http_code
    })


# ══════════════════════════════════════════════════════════════════════════════
# Rotas originais
# ══════════════════════════════════════════════════════════════════════════════

@ app.route('/api/settings/', methods=['GET', 'PUT'])
def handle_settings():
    if request.method == 'PUT':
        data = request.get_json()
        for key, value in data.items():
            update_setting(key, value)
    result = get_settings()
    if 'meta_mensal' in result:
        result['meta_mensal'] = float(result['meta_mensal'])
    return jsonify(result)


@ app.route('/')
def index():
    return send_from_directory(STATIC_DIR, 'index.html')


@ app.route('/css/<path:filename>')
def css(filename):
    return send_from_directory(os.path.join(STATIC_DIR, 'css'), filename)


@ app.route('/js/<path:filename>')
def js(filename):
    return send_from_directory(os.path.join(STATIC_DIR, 'js'), filename)


@ app.route('/api/stats')
def stats():
    return jsonify(get_stats())


@ app.route('/api/migrate/sql', methods=['GET'])
def migrate_sql():
    sql_path = os.path.join(os.path.dirname(__file__), 'db', 'supabase_schema.sql')
    with open(sql_path) as f:
        return f.read(), 200, {'Content-Type': 'text/plain; charset=utf-8'}


@ app.errorhandler(404)
def not_found(e):
    return jsonify({'error': 'Rota não encontrada'}), 404


@ app.errorhandler(500)
def server_error(e):
    return jsonify({'error': 'Erro interno do servidor'}), 500


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3001, debug=True)
