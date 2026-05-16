import os
import datetime
import requests
from flask import Flask, jsonify, send_from_directory, request
from flask_cors import CORS
from db.database import get_db, get_settings, update_setting, get_stats
from routes.clients import clients_bp
from routes.appointments import appointments_bp
from routes.services import services_bp

STATIC_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'src')

# ─── URL do webhook gerada pelo n8n ────────────────────────────────────────────
# Substitua pelo valor real após criar o workflow no n8n
N8N_WEBHOOK_URL = os.environ.get(
    "N8N_WEBHOOK_URL",
    "https://mirianfiorini.app.n8n.cloud/webhook/calendar-webhook"  # <-- troque aqui
)
# ───────────────────────────────────────────────────────────────────────────────

app = Flask(__name__, static_folder=None)
CORS(app)

app.register_blueprint(clients_bp, url_prefix='/api/clients')
app.register_blueprint(appointments_bp, url_prefix='/api/appointments')
app.register_blueprint(services_bp, url_prefix='/api/services')


# ══════════════════════════════════════════════════════════════════════════════
# NOVO ENDPOINT — Dispara sincronização de agendamento com o Google Calendar
# via n8n. Não altera nenhuma rota existente.
#
# Como usar (chamar do seu frontend ou de routes/appointments.py após salvar):
#
#   POST /api/n8n/sync-calendar
#   Body JSON:
#   {
#     "action":          "create" | "update" | "delete",
#     "appointment_id":  123,
#     "client_name":     "Maria Silva",
#     "client_phone":    "11999999999",
#     "service":         "Corte + Escova",
#     "price":           150.0,
#     "status":          "confirmed",
#     "appointment_date": "2026-05-20",        -- formato YYYY-MM-DD
#     "appointment_time": "14:30",             -- formato HH:MM
#     "duration_minutes": 60,                  -- opcional, padrão 60
#     "google_event_id": "abc123xyz"           -- obrigatório só para action=delete
#   }
# ══════════════════════════════════════════════════════════════════════════════
@app.route('/api/n8n/sync-calendar', methods=['POST'])
def n8n_sync_calendar():
    data = request.get_json(force=True)

    # Campos obrigatórios para create/update
    required_fields = ['action', 'appointment_id', 'appointment_date', 'appointment_time']
    missing = [f for f in required_fields if f not in data]
    if missing:
        return jsonify({'error': f'Campos obrigatórios ausentes: {", ".join(missing)}'}), 400

    action = data.get('action', 'create')

    # Para delete, apenas o google_event_id é necessário além do action
    if action == 'delete' and not data.get('google_event_id'):
        return jsonify({'error': 'google_event_id é obrigatório para action=delete'}), 400

    # Monta datetimes no formato ISO 8601 que o Google Calendar espera
    try:
        appt_date = data['appointment_date']            # "2026-05-20"
        appt_time = data['appointment_time']            # "14:30"
        duration  = int(data.get('duration_minutes', 60))

        start_dt = datetime.datetime.strptime(
            f"{appt_date} {appt_time}", "%Y-%m-%d %H:%M"
        )
        end_dt = start_dt + datetime.timedelta(minutes=duration)

        # Fuso horário de São Paulo (UTC-3)
        tz_suffix = "-03:00"
        start_iso = start_dt.strftime("%Y-%m-%dT%H:%M:%S") + tz_suffix
        end_iso   = end_dt.strftime("%Y-%m-%dT%H:%M:%S") + tz_suffix
    except (ValueError, KeyError) as e:
        return jsonify({'error': f'Formato de data/hora inválido: {str(e)}'}), 400

    # Payload enviado ao n8n
    payload = {
        "action":           action,
        "appointment_id":   data.get('appointment_id'),
        "client_name":      data.get('client_name', 'Cliente'),
        "client_phone":     data.get('client_phone', ''),
        "service":          data.get('service', 'Serviço'),
        "price":            data.get('price', 0),
        "status":           data.get('status', 'pending'),
        "start_datetime":   start_iso,
        "end_datetime":     end_iso,
        "google_event_id":  data.get('google_event_id', ''),
    }

    # Dispara o webhook do n8n
    try:
        n8n_response = requests.post(
            N8N_WEBHOOK_URL,
            json=payload,
            timeout=8
        )
        n8n_response.raise_for_status()
        return jsonify({
            'status': 'ok',
            'message': 'Sincronização enviada ao n8n com sucesso',
            'n8n_status': n8n_response.status_code,
            'payload_enviado': payload
        }), 200

    except requests.exceptions.Timeout:
        return jsonify({'error': 'Timeout ao conectar com o n8n. Verifique se o n8n está rodando.'}), 504

    except requests.exceptions.ConnectionError:
        return jsonify({'error': 'Não foi possível conectar ao n8n. Verifique a N8N_WEBHOOK_URL.'}), 502

    except requests.exceptions.HTTPError as e:
        return jsonify({'error': f'n8n retornou erro: {str(e)}'}), 502

    except Exception as e:
        return jsonify({'error': f'Erro inesperado: {str(e)}'}), 500


# ──────────────────────────────────────────────────────────────────────────────
# Endpoint auxiliar: retorna a URL configurada e testa conectividade com o n8n
# GET /api/n8n/status
# ──────────────────────────────────────────────────────────────────────────────
@app.route('/api/n8n/status', methods=['GET'])
def n8n_status():
    try:
        resp = requests.get(N8N_WEBHOOK_URL, timeout=5)
        online = True
        http_code = resp.status_code
    except Exception:
        online = False
        http_code = None

    return jsonify({
        'n8n_webhook_url': N8N_WEBHOOK_URL,
        'n8n_reachable': online,
        'n8n_http_code': http_code
    })


# ══════════════════════════════════════════════════════════════════════════════
# Rotas originais — NENHUMA ALTERAÇÃO
# ══════════════════════════════════════════════════════════════════════════════

@app.route('/api/settings/', methods=['GET', 'PUT'])
def handle_settings():
    if request.method == 'PUT':
        data = request.get_json()
        for key, value in data.items():
            update_setting(key, value)
    result = get_settings()
    if 'meta_mensal' in result:
        result['meta_mensal'] = float(result['meta_mensal'])
    return jsonify(result)


@app.route('/')
def index():
    return send_from_directory(STATIC_DIR, 'index.html')


@app.route('/css/<path:filename>')
def css(filename):
    return send_from_directory(os.path.join(STATIC_DIR, 'css'), filename)


@app.route('/js/<path:filename>')
def js(filename):
    return send_from_directory(os.path.join(STATIC_DIR, 'js'), filename)


@app.route('/api/stats')
def stats():
    return jsonify(get_stats())


@app.errorhandler(404)
def not_found(e):
    return jsonify({'error': 'Rota não encontrada'}), 404


@app.errorhandler(500)
def server_error(e):
    return jsonify({'error': 'Erro interno do servidor'}), 500


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3001, debug=True)
