from flask import Blueprint, request, jsonify
from db.database import get_db, get_settings
from middleware.validation import validate_appointment
import threading, requests, datetime

appointments_bp = Blueprint('appointments', __name__)


def _first(table, column, value):
    r = get_db().table(table).select('*').eq(column, value).limit(1).execute()
    return r.data[0] if r.data else None


def _get_appt(appt_id):
    supabase = get_db()
    r = supabase.table('appointments').select('*, clients(name, phone)').eq('id', appt_id).limit(1).execute()
    if not r.data:
        return None
    a = r.data[0]
    if isinstance(a.get('clients'), dict):
        a['client_name'] = a['clients'].get('name', '')
        a['client_phone'] = a['clients'].get('phone', '')
    return a


def _fmt_time(t):
    return t[:5] if t and len(t) >= 5 else (t or '')


def format_appt(a):
    return {
        'id': a['id'],
        'client_id': a['client_id'],
        'client_name': a.get('client_name') or '',
        'client_phone': a.get('client_phone') or '',
        'service': a['service'],
        'appointment_date': a['appointment_date'],
        'appointment_time': _fmt_time(a.get('appointment_time')),
        'status': a['status'],
        'price': a['price'],
        'duration': a['duration'],
        'notes': a.get('notes', ''),
        'created_at': a.get('created_at'),
        'updated_at': a.get('updated_at'),
    }


def _n8n_payload(a):
    appt_date = a['appointment_date']
    appt_time = a.get('appointment_time', '12:00')[:5]
    duration  = int(a.get('duration', 60))
    try:
        start_dt = datetime.datetime.strptime(f"{appt_date} {appt_time}", "%Y-%m-%d %H:%M")
        end_dt = start_dt + datetime.timedelta(minutes=duration)
        tz = "-03:00"
        start_iso = start_dt.strftime("%Y-%m-%dT%H:%M:%S") + tz
        end_iso   = end_dt.strftime("%Y-%m-%dT%H:%M:%S") + tz
    except Exception:
        start_iso = appt_date + 'T' + appt_time + ':00-03:00'
        end_iso   = start_iso
    return {
        'action': 'create',
        'appointment_id': a['id'],
        'client_name': a.get('client_name', ''),
        'client_phone': a.get('client_phone', ''),
        'service': a['service'],
        'price': a['price'],
        'status': a['status'],
        'start_datetime': start_iso,
        'end_datetime': end_iso,
        'google_event_id': '',
    }


def _fire_n8n(a):
    try:
        settings = get_settings()
        url = settings.get('n8n_webhook_url', '').strip()
        if not url:
            import os
            url = os.environ.get('N8N_WEBHOOK_URL', '')
        if not url:
            return
        payload = _n8n_payload(a)
        threading.Thread(target=lambda: requests.post(url, json=payload, timeout=8), daemon=True).start()
    except Exception:
        pass


@appointments_bp.route('/', methods=['GET'])
def list_appointments():
    supabase = get_db()
    query = supabase.table('appointments').select('*, clients!inner(name, phone)')
    date = request.args.get('date')
    client_id = request.args.get('client_id')
    status = request.args.get('status')
    date_from = request.args.get('date_from')
    date_to = request.args.get('date_to')

    if date:
        query = query.eq('appointment_date', date)
    if date_from:
        query = query.gte('appointment_date', date_from)
    if date_to:
        query = query.lte('appointment_date', date_to)
    if client_id:
        query = query.eq('client_id', int(client_id))
    if status:
        query = query.eq('status', status)

    result = query.order('appointment_date').order('appointment_time').execute()
    rows = []
    for a in result.data:
        a['client_name'] = a.get('clients', {}).get('name', '') if isinstance(a.get('clients'), dict) else ''
        a['client_phone'] = a.get('clients', {}).get('phone', '') if isinstance(a.get('clients'), dict) else ''
        rows.append(a)
    return jsonify([format_appt(r) for r in rows])


@appointments_bp.route('/<int:appt_id>', methods=['GET'])
def get_appointment(appt_id):
    a = _get_appt(appt_id)
    if not a:
        return jsonify({'error': 'Agendamento n\u00e3o encontrado'}), 404
    return jsonify(format_appt(a))


@appointments_bp.route('/', methods=['POST'])
@validate_appointment
def create_appointment():
    data = request.get_json()
    client = _first('clients', 'id', data['client_id'])
    if not client:
        return jsonify({'error': 'Cliente n\u00e3o encontrado'}), 400

    supabase = get_db()
    result = supabase.table('appointments').insert({
        'client_id': data['client_id'],
        'service': data['service'],
        'appointment_date': data['appointment_date'],
        'appointment_time': data['appointment_time'],
        'status': data.get('status', 'pending'),
        'price': float(data['price']),
        'duration': data.get('duration', 60),
        'notes': data.get('notes', ''),
    }).execute()
    a = result.data[0]
    a['client_name'] = client.get('name', '')
    a['client_phone'] = client.get('phone', '')
    _fire_n8n(a)
    return jsonify(format_appt(a)), 201


@appointments_bp.route('/<int:appt_id>', methods=['PUT'])
def update_appointment(appt_id):
    existing = _first('appointments', 'id', appt_id)
    if not existing:
        return jsonify({'error': 'Agendamento n\u00e3o encontrado'}), 404

    data = request.get_json()
    update_data = {}
    for field in ['client_id', 'service', 'appointment_date', 'appointment_time', 'status', 'duration', 'notes']:
        if field in data and data[field] is not None:
            update_data[field] = data[field]
    if 'price' in data and data['price'] is not None:
        update_data['price'] = float(data['price'])
    if update_data:
        get_db().table('appointments').update(update_data).eq('id', appt_id).execute()

    a = _get_appt(appt_id)
    return jsonify(format_appt(a))


@appointments_bp.route('/<int:appt_id>', methods=['DELETE'])
def delete_appointment(appt_id):
    existing = _first('appointments', 'id', appt_id)
    if not existing:
        return jsonify({'error': 'Agendamento n\u00e3o encontrado'}), 404
    get_db().table('appointments').delete().eq('id', appt_id).execute()
    return jsonify({'message': 'Agendamento removido', 'id': appt_id})
