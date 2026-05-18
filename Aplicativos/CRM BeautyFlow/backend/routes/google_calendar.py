import os
import json
import datetime
from flask import Blueprint, request, jsonify, redirect
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request as AuthRequest
from googleapiclient.discovery import build
from requests_oauthlib import OAuth2Session
from db.database import get_settings, update_setting

google_bp = Blueprint('google', __name__)

SCOPES = ['https://www.googleapis.com/auth/calendar.events']
AUTH_URI = 'https://accounts.google.com/o/oauth2/auth'
TOKEN_URI = 'https://oauth2.googleapis.com/token'


def _get_credentials():
    s = get_settings()
    creds_json = s.get('google_credentials', '')
    if not creds_json:
        return None
    try:
        creds = Credentials.from_authorized_user_info(json.loads(creds_json), SCOPES)
        return creds
    except Exception:
        return None


def _save_credentials(creds):
    update_setting('google_credentials', json.dumps(json.loads(creds.to_json())))


def _get_client_config():
    s = get_settings()
    return s.get('google_client_id', '').strip(), s.get('google_client_secret', '').strip()


def _refresh_creds(creds):
    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(AuthRequest())
            _save_credentials(creds)
            return creds
        except Exception:
            return None
    return creds


def sync_appointment_to_google(action, appointment_data):
    creds = _get_credentials()
    if not creds:
        return {'error': 'Google Calendar não conectado.'}

    creds = _refresh_creds(creds)
    if not creds:
        return {'error': 'Token Google expirado. Reconecte.'}

    try:
        service = build('calendar', 'v3', credentials=creds)
    except Exception as e:
        return {'error': f'Erro ao conectar Google Calendar: {str(e)}'}

    appt_date = appointment_data.get('appointment_date', '')
    appt_time = (appointment_data.get('appointment_time') or '12:00')[:5]
    duration = int(appointment_data.get('duration', 60))

    try:
        start_dt = datetime.datetime.strptime(f"{appt_date} {appt_time}", "%Y-%m-%d %H:%M")
        end_dt = start_dt + datetime.timedelta(minutes=duration)
    except Exception:
        return {'error': 'Formato de data/hora inválido.'}

    start_iso = start_dt.isoformat() + '-03:00'
    end_iso = end_dt.isoformat() + '-03:00'

    event = {
        'summary': f"{appointment_data.get('service', 'Serviço')} — {appointment_data.get('client_name', 'Cliente')}",
        'description': (
            f"Cliente: {appointment_data.get('client_name', '')}\n"
            f"Telefone: {appointment_data.get('client_phone', '')}\n"
            f"Valor: R$ {appointment_data.get('price', 0):.2f}\n"
            f"Status: {appointment_data.get('status', 'pending')}\n"
            f"ID: {appointment_data.get('appointment_id', '')}"
        ),
        'start': {'dateTime': start_iso, 'timeZone': 'America/Sao_Paulo'},
        'end':   {'dateTime': end_iso,   'timeZone': 'America/Sao_Paulo'},
    }

    google_event_id = appointment_data.get('google_event_id', '')

    try:
        if action == 'delete':
            if not google_event_id:
                return {'error': 'google_event_id é obrigatório para exclusão'}
            service.events().delete(calendarId='primary', eventId=google_event_id).execute()
            return {'status': 'ok', 'action': 'deleted'}
        if action == 'update' and google_event_id:
            updated = service.events().update(calendarId='primary', eventId=google_event_id, body=event).execute()
            return {'status': 'ok', 'action': 'updated', 'google_event_id': updated['id'], 'html_link': updated.get('htmlLink', '')}
        created = service.events().insert(calendarId='primary', body=event).execute()
        return {'status': 'ok', 'action': 'created', 'google_event_id': created['id'], 'html_link': created.get('htmlLink', '')}
    except Exception as e:
        return {'error': f'Google Calendar: {str(e)}'}


@google_bp.route('/config', methods=['GET', 'PUT'])
def google_config():
    if request.method == 'PUT':
        data = request.get_json()
        update_setting('google_client_id', (data.get('client_id') or '').strip())
        update_setting('google_client_secret', (data.get('client_secret') or '').strip())
        return jsonify({'status': 'ok'})

    s = get_settings()
    return jsonify({
        'client_id': s.get('google_client_id', ''),
        'client_secret': s.get('google_client_secret', '') and '••••••' or '',
    })


@google_bp.route('/auth')
def google_auth():
    client_id, client_secret = _get_client_config()
    if not client_id or not client_secret:
        return jsonify({'error': 'Configure Client ID e Client Secret primeiro.'}), 400

    redirect_uri = request.host_url.rstrip('/') + '/api/google/callback'

    oauth = OAuth2Session(client_id, redirect_uri=redirect_uri, scope=SCOPES)
    auth_url, state = oauth.authorization_url(
        AUTH_URI, access_type='offline', prompt='consent'
    )

    return jsonify({'auth_url': auth_url, 'state': state})


@google_bp.route('/callback')
def google_callback():
    code = request.args.get('code')
    error = request.args.get('error')
    state = request.args.get('state', '')
    if error:
        return redirect(request.host_url + '?google_error=' + error)
    if not code:
        return jsonify({'error': 'Código de autorização não recebido.'}), 400

    client_id, client_secret = _get_client_config()
    if not client_id or not client_secret:
        return jsonify({'error': 'Configure Client ID e Client Secret primeiro.'}), 400

    redirect_uri = request.host_url.rstrip('/') + '/api/google/callback'

    try:
        oauth = OAuth2Session(client_id, redirect_uri=redirect_uri, scope=SCOPES, state=state)
        token = oauth.fetch_token(
            TOKEN_URI, client_secret=client_secret, code=code
        )

        creds = Credentials(
            token=token.get('access_token'),
            refresh_token=token.get('refresh_token'),
            token_uri=TOKEN_URI,
            client_id=client_id,
            client_secret=client_secret,
            scopes=SCOPES,
        )
        _save_credentials(creds)
        return redirect(request.host_url + '?google_connected=1')
    except Exception as e:
        return redirect(request.host_url + '?google_error=' + str(e))


@google_bp.route('/status')
def google_status():
    creds = _get_credentials()
    if not creds:
        return jsonify({'connected': False})
    creds = _refresh_creds(creds)
    if not creds:
        return jsonify({'connected': False})
    return jsonify({'connected': True})


@google_bp.route('/disconnect', methods=['POST'])
def google_disconnect():
    update_setting('google_credentials', '')
    return jsonify({'status': 'ok'})


@google_bp.route('/verify-event', methods=['POST'])
def verify_event():
    data = request.get_json(force=True)
    event_id = data.get('event_id', '')
    if not event_id:
        return jsonify({'exists': False, 'error': 'event_id obrigatório'}), 400

    creds = _get_credentials()
    if not creds:
        return jsonify({'exists': False, 'error': 'Google não conectado'})

    creds = _refresh_creds(creds)
    if not creds:
        return jsonify({'exists': False, 'error': 'Token expirado'})

    try:
        service = build('calendar', 'v3', credentials=creds)
        service.events().get(calendarId='primary', eventId=event_id).execute()
        return jsonify({'exists': True})
    except Exception as e:
        err = str(e)
        if '404' in err or 'not found' in err.lower():
            return jsonify({'exists': False})
        return jsonify({'exists': False, 'error': err})


@google_bp.route('/sync', methods=['POST'])
def google_sync():
    data = request.get_json(force=True)
    action = data.get('action', 'create')
    result = sync_appointment_to_google(action, data)
    if 'error' in result:
        return jsonify(result), 400
    return jsonify(result)
