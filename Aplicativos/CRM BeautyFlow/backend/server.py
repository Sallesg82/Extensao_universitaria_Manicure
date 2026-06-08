import os
import datetime
import requests
from dotenv import load_dotenv
from flask import Flask, jsonify, send_from_directory, request
from flask_cors import CORS
import json
from ws import socketio
from db.database import get_db, get_settings, update_setting, get_stats, unread_notifications_count, create_notification, load_business_hours, save_business_hours, _migrate_business_hours, DAYS_PT
from postgrest.exceptions import APIError
from routes.clients import clients_bp
from routes.appointments import appointments_bp
from routes.services import services_bp
from routes.users import users_bp
from routes.google_calendar import google_bp
from routes.notifications import notifications_bp
from routes.integrations import integrations_bp
from routes.transactions import transactions_bp

load_dotenv()

STATIC_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'src')

app = Flask(__name__, static_folder=None)
CORS(app)
socketio.init_app(app, cors_allowed_origins="*", async_mode='threading')

app.register_blueprint(clients_bp, url_prefix='/api/clients')
app.register_blueprint(appointments_bp, url_prefix='/api/appointments')
app.register_blueprint(services_bp, url_prefix='/api/services')
app.register_blueprint(users_bp, url_prefix='/api/users')
app.register_blueprint(google_bp, url_prefix='/api/google')
app.register_blueprint(notifications_bp, url_prefix='/api/notifications')
app.register_blueprint(integrations_bp, url_prefix='/api/integrations')
app.register_blueprint(transactions_bp, url_prefix='/api/transactions')


# ─── Helpers de configuração n8n ────────────────────────────────────────────
_N8N_FALLBACK = 'https://mirianfiorini.app.n8n.cloud/webhook/calendar-webhook'

def _n8n_settings():
    try:
        s = get_settings()
        return {
            'n8n_enabled': s.get('n8n_enabled', 'true'),
            'n8n_webhook_url': s.get('n8n_webhook_url', ''),
            'n8n_events': s.get('n8n_events', 'create,update,delete'),
            'n8n_timeout': s.get('n8n_timeout', '8'),
            'n8n_header_name': s.get('n8n_header_name', ''),
            'n8n_header_value': s.get('n8n_header_value', ''),
        }
    except Exception:
        return {}

def _n8n_enabled():
    return _n8n_settings().get('n8n_enabled', 'true') == 'true'

def _n8n_webhook_url():
    cfg = _n8n_settings()
    url = cfg.get('n8n_webhook_url', '').strip()
    return url or os.environ.get('N8N_WEBHOOK_URL', _N8N_FALLBACK)

def _n8n_timeout():
    cfg = _n8n_settings()
    try:
        return int(cfg.get('n8n_timeout', '8'))
    except (ValueError, TypeError):
        return 8

def _n8n_headers():
    cfg = _n8n_settings()
    name = cfg.get('n8n_header_name', '').strip()
    value = cfg.get('n8n_header_value', '').strip()
    return {name: value} if name and value else {}

def _n8n_should_fire(action):
    cfg = _n8n_settings()
    events = cfg.get('n8n_events', 'create,update,delete').split(',')
    return action in events


# ══════════════════════════════════════════════════════════════════════════════
# Endpoints de configuração do n8n
# ══════════════════════════════════════════════════════════════════════════════

@ app.route('/api/n8n/config', methods=['GET', 'PUT'])
def n8n_config():
    if request.method == 'PUT':
        data = request.get_json()
        for key in ('n8n_enabled', 'n8n_webhook_url', 'n8n_events', 'n8n_timeout', 'n8n_header_name', 'n8n_header_value'):
            if key in data:
                update_setting(key, data[key])
        return jsonify({'status': 'ok'})

    return jsonify(_n8n_settings())


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
        r = requests.post(url, json=payload, headers=_n8n_headers(), timeout=_n8n_timeout())
        r.raise_for_status()
        return jsonify({
            'status': 'ok',
            'message': 'Webhook enviado com sucesso!',
            'n8n_status': r.status_code,
            'n8n_response': r.text[:500],
        })
    except requests.exceptions.Timeout:
        return jsonify({'error': f'Timeout — n8n não respondeu em {_n8n_timeout()} segundos.'}), 504
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

    if not _n8n_enabled():
        return jsonify({'error': 'Integração n8n desabilitada.'}), 400
    url = _n8n_webhook_url()
    try:
        n8n_response = requests.post(url, json=payload, headers=_n8n_headers(), timeout=_n8n_timeout())
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
    cfg = _n8n_settings()
    url = _n8n_webhook_url()
    try:
        resp = requests.get(url, timeout=5)
        online = True
        http_code = resp.status_code
    except Exception:
        online = False
        http_code = None
    return jsonify({
        'n8n_enabled': cfg.get('n8n_enabled', 'true') == 'true',
        'n8n_webhook_url': url,
        'n8n_events': cfg.get('n8n_events', 'create,update,delete'),
        'n8n_timeout': int(cfg.get('n8n_timeout', 8)),
        'n8n_reachable': online,
        'n8n_http_code': http_code
    })


# ══════════════════════════════════════════════════════════════════════════════
# Rotas originais
# ══════════════════════════════════════════════════════════════════════════════

@ app.route('/api/settings/', methods=['GET', 'PUT'])
def handle_settings():
    if request.method == 'PUT':
        data = request.get_json(silent=True) or {}
        for key, value in data.items():
            update_setting(key, value)
    result = get_settings()
    if 'meta_mensal' in result:
        result['meta_mensal'] = float(result['meta_mensal'])
    return jsonify(result)


# ══════════════════════════════════════════════════════════════════════════════
# Business Hours (horários de funcionamento)
# ══════════════════════════════════════════════════════════════════════════════

_migrate_business_hours()

@app.route('/api/business-hours', methods=['GET', 'PUT'])
def business_hours():
    if request.method == 'PUT':
        data = request.get_json(silent=True) or {}
        save_business_hours(data)
        return jsonify({'status': 'ok'})
    return jsonify(load_business_hours())


@app.route('/api/available-slots', methods=['GET'])
def available_slots():
    date_str = request.args.get('date', '')
    duration = request.args.get('duration', '60')
    buffer = request.args.get('buffer', '0')
    if not date_str:
        return jsonify({'error': 'Parâmetro "date" é obrigatório (YYYY-MM-DD)'}), 400
    try:
        duration = int(duration)
    except (ValueError, TypeError):
        duration = 60
    try:
        buffer = int(buffer)
    except (ValueError, TypeError):
        buffer = 0

    total = duration + buffer

    try:
        dt = datetime.datetime.strptime(date_str, '%Y-%m-%d')
    except ValueError:
        return jsonify({'error': 'Formato de data inválido. Use YYYY-MM-DD'}), 400

    dow = dt.weekday()
    day_key = DAYS_PT[dow]

    hours = load_business_hours()
    day_hours = hours.get(day_key, {})

    if day_hours.get('closed', False):
        return jsonify({
            'date': date_str,
            'day': day_key,
            'duration': duration,
            'buffer': buffer,
            'closed': True,
            'slots': [],
            'message': 'Fechado neste dia'
        })

    open_str = day_hours.get('open', '08:00')
    close_str = day_hours.get('close', '18:00')

    try:
        open_min = int(open_str.split(':')[0]) * 60 + int(open_str.split(':')[1])
        close_min = int(close_str.split(':')[0]) * 60 + int(close_str.split(':')[1])
    except (ValueError, IndexError):
        return jsonify({'error': 'Horário de funcionamento inválido'}), 500

    supabase = get_db()
    svc_buffers = {}
    try:
        svc_list = supabase.table('services').select('name,buffer').execute()
        svc_buffers = {s['name']: int(s.get('buffer', 0) or 0) for s in svc_list.data}
    except APIError:
        try:
            svc_list = supabase.table('services').select('name').execute()
            svc_buffers = {s['name']: 0 for s in svc_list.data}
        except APIError:
            pass

    # Buscar agendamentos existentes para esta data
    existing = supabase.table('appointments').select('appointment_time,duration,service').eq('appointment_date', date_str).neq('status', 'cancelled').execute()
    occupied = []
    for a in existing.data:
        try:
            t = a.get('appointment_time', '')
            if isinstance(t, str) and ':' in t:
                parts = t.split(':')
                start = int(parts[0]) * 60 + int(parts[1])
                dur = int(a.get('duration', 60))
                svc_buffer = svc_buffers.get(a.get('service', ''), 0)
                occupied.append({'start': start, 'end': start + dur + svc_buffer})
        except (ValueError, IndexError):
            pass

    # Gerar slots a cada 30 minutos
    slot_step = 30
    slots = []
    slot_start = open_min
    while slot_start + total <= close_min:
        slot_end = slot_start + total
        conflict = False
        for occ in occupied:
            if slot_start < occ['end'] and slot_end > occ['start']:
                conflict = True
                break
        if not conflict:
            h = slot_start // 60
            m = slot_start % 60
            slots.append(f"{h:02d}:{m:02d}")
        slot_start += slot_step

    return jsonify({
        'date': date_str,
        'day': day_key,
        'duration': duration,
        'buffer': buffer,
        'closed': False,
        'open': open_str,
        'close': close_str,
        'slots': slots,
    })


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
    period = request.args.get('period', 0, type=int)
    data = get_stats(period=period if period > 0 else None)
    data['notifications_unread'] = unread_notifications_count()

    if data.get('month_revenue', 0) >= data.get('meta_mensal', 0) and data.get('meta_mensal', 0) > 0:
        settings = get_settings()
        if settings.get('notify_alerta_de_meta_atingida', 'true') == 'true':
            existing = get_db().table('notifications').select('id').eq('type', 'meta_atingida').limit(1).execute()
            if not existing.data:
                create_notification(
                    'meta_atingida',
                    'Meta Mensal Atingida!',
                    f"Parabéns! A meta de R$ {data['meta_mensal']:,.0f} foi alcançada. Receita atual: R$ {data['month_revenue']:,.2f}"
                )
                data['notifications_unread'] = unread_notifications_count()

    return jsonify(data)


@ app.route('/api/migrate/sql', methods=['GET'])
def migrate_sql():
    sql_path = os.path.join(os.path.dirname(__file__), 'db', 'supabase_schema.sql')
    try:
        with open(sql_path) as f:
            return f.read(), 200, {'Content-Type': 'text/plain; charset=utf-8'}
    except FileNotFoundError:
        return jsonify({'error': 'Arquivo de schema SQL não encontrado'}), 404


@app.route('/api/expense-categories', methods=['GET'])
def list_expense_categories():
    settings = get_settings()
    raw = settings.get('expense_categories', '[]')
    try:
        cats = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        cats = []
    return jsonify(cats)


@app.route('/api/expense-categories', methods=['POST'])
def create_expense_category():
    data = request.get_json()
    name = (data.get('name') or '').strip()
    if not name:
        return jsonify({'error': 'Nome da categoria é obrigatório'}), 400
    settings = get_settings()
    raw = settings.get('expense_categories', '[]')
    try:
        cats = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        cats = []
    if any(c['name'].lower() == name.lower() for c in cats):
        return jsonify({'error': 'Categoria já existe'}), 409
    new_cat = {'name': name, 'id': str(len(cats) + 1)}
    cats.append(new_cat)
    update_setting('expense_categories', json.dumps(cats, ensure_ascii=False))
    return jsonify(new_cat), 201


@app.errorhandler(404)
def not_found(e):
    return jsonify({'error': 'Rota não encontrada'}), 404


@ app.errorhandler(500)
def server_error(e):
    return jsonify({'error': 'Erro interno do servidor'}), 500


if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=3001, debug=False, allow_unsafe_werkzeug=True)
