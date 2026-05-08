from flask import Blueprint, request, jsonify
from db.database import get_db
from middleware.validation import validate_appointment

appointments_bp = Blueprint('appointments', __name__)


def format_appt(a):
    return {
        'id': a['id'],
        'client_id': a['client_id'],
        'client_name': a['client_name'] or '',
        'client_phone': a['client_phone'] or '',
        'service': a['service'],
        'appointment_date': a['appointment_date'],
        'appointment_time': a['appointment_time'],
        'status': a['status'],
        'price': a['price'],
        'duration': a['duration'],
        'notes': a['notes'],
        'created_at': a['created_at'],
        'updated_at': a['updated_at'],
    }


@appointments_bp.route('/', methods=['GET'])
def list_appointments():
    conn = get_db()
    date = request.args.get('date')
    client_id = request.args.get('client_id')
    status = request.args.get('status')

    sql = """
        SELECT a.*, c.name as client_name, c.phone as client_phone
        FROM appointments a
        JOIN clients c ON c.id = a.client_id
        WHERE 1=1
    """
    params = []
    if date:
        sql += " AND a.appointment_date = ?"
        params.append(date)
    date_from = request.args.get('date_from')
    date_to = request.args.get('date_to')
    if date_from:
        sql += " AND a.appointment_date >= ?"
        params.append(date_from)
    if date_to:
        sql += " AND a.appointment_date <= ?"
        params.append(date_to)
    if client_id:
        sql += " AND a.client_id = ?"
        params.append(int(client_id))
    if status:
        sql += " AND a.status = ?"
        params.append(status)
    sql += " ORDER BY a.appointment_date ASC, a.appointment_time ASC"

    rows = conn.execute(sql, params).fetchall()
    return jsonify([format_appt(r) for r in rows])


@appointments_bp.route('/<int:appt_id>', methods=['GET'])
def get_appointment(appt_id):
    conn = get_db()
    a = conn.execute("""
        SELECT a.*, c.name as client_name, c.phone as client_phone
        FROM appointments a
        JOIN clients c ON c.id = a.client_id
        WHERE a.id = ?
    """, (appt_id,)).fetchone()
    if not a:
        return jsonify({'error': 'Agendamento não encontrado'}), 404
    return jsonify(format_appt(a))


@appointments_bp.route('/', methods=['POST'])
@validate_appointment
def create_appointment():
    data = request.get_json()
    conn = get_db()

    client = conn.execute("SELECT id FROM clients WHERE id = ?", (data['client_id'],)).fetchone()
    if not client:
        return jsonify({'error': 'Cliente não encontrado'}), 400

    cur = conn.execute(
        "INSERT INTO appointments (client_id, service, appointment_date, appointment_time, status, price, duration, notes) VALUES (?,?,?,?,?,?,?,?)",
        (data['client_id'], data['service'], data['appointment_date'], data['appointment_time'],
         data.get('status', 'pending'), float(data['price']), data.get('duration', 60), data.get('notes', ''))
    )
    conn.commit()

    a = conn.execute("""
        SELECT a.*, c.name as client_name, c.phone as client_phone
        FROM appointments a JOIN clients c ON c.id = a.client_id
        WHERE a.id = ?
    """, (cur.lastrowid,)).fetchone()
    return jsonify(format_appt(a)), 201


@appointments_bp.route('/<int:appt_id>', methods=['PUT'])
def update_appointment(appt_id):
    conn = get_db()
    existing = conn.execute("SELECT * FROM appointments WHERE id = ?", (appt_id,)).fetchone()
    if not existing:
        return jsonify({'error': 'Agendamento não encontrado'}), 404

    data = request.get_json()

    conn.execute("""
        UPDATE appointments SET
            client_id = COALESCE(?, client_id),
            service = COALESCE(?, service),
            appointment_date = COALESCE(?, appointment_date),
            appointment_time = COALESCE(?, appointment_time),
            status = COALESCE(?, status),
            price = COALESCE(?, price),
            duration = COALESCE(?, duration),
            notes = COALESCE(?, notes),
            updated_at = datetime('now', 'localtime')
        WHERE id = ?
    """, (
        data.get('client_id'), data.get('service'), data.get('appointment_date'),
        data.get('appointment_time'), data.get('status'),
        float(data['price']) if data.get('price') is not None else None,
        data.get('duration'), data.get('notes'),
        appt_id
    ))
    conn.commit()

    a = conn.execute("""
        SELECT a.*, c.name as client_name, c.phone as client_phone
        FROM appointments a JOIN clients c ON c.id = a.client_id
        WHERE a.id = ?
    """, (appt_id,)).fetchone()
    return jsonify(format_appt(a))


@appointments_bp.route('/<int:appt_id>', methods=['DELETE'])
def delete_appointment(appt_id):
    conn = get_db()
    existing = conn.execute("SELECT * FROM appointments WHERE id = ?", (appt_id,)).fetchone()
    if not existing:
        return jsonify({'error': 'Agendamento não encontrado'}), 404
    conn.execute("DELETE FROM appointments WHERE id = ?", (appt_id,))
    conn.commit()
    return jsonify({'message': 'Agendamento removido', 'id': appt_id})
