from flask import Blueprint, request, jsonify
from db.database import get_db
from middleware.validation import validate_client

clients_bp = Blueprint('clients', __name__)


def format_client(c):
    return {
        'id': c['id'],
        'name': c['name'],
        'phone': c['phone'],
        'email': c['email'],
        'avatar_initials': c['avatar_initials'],
        'avatar_bg': c['avatar_bg'],
        'avatar_color': c['avatar_color'],
        'notes': c['notes'],
        'status': c['status'],
        'visits': c['visits'] or 0,
        'total_spent': c['total_spent'] or 0,
        'last_visit': c['last_visit'],
        'created_at': c['created_at'],
        'updated_at': c['updated_at'],
    }


@clients_bp.route('/', methods=['GET'])
def list_clients():
    conn = get_db()
    rows = conn.execute("""
        SELECT c.*,
            (SELECT COUNT(*) FROM appointments WHERE client_id = c.id) as visits,
            (SELECT COALESCE(SUM(price), 0) FROM appointments WHERE client_id = c.id) as total_spent,
            (SELECT MAX(appointment_date) FROM appointments WHERE client_id = c.id) as last_visit
        FROM clients c
        ORDER BY c.name ASC
    """).fetchall()
    return jsonify([format_client(r) for r in rows])


@clients_bp.route('/<int:client_id>', methods=['GET'])
def get_client(client_id):
    conn = get_db()
    c = conn.execute("""
        SELECT c.*,
            (SELECT COUNT(*) FROM appointments WHERE client_id = c.id) as visits,
            (SELECT COALESCE(SUM(price), 0) FROM appointments WHERE client_id = c.id) as total_spent,
            (SELECT MAX(appointment_date) FROM appointments WHERE client_id = c.id) as last_visit
        FROM clients c WHERE c.id = ?
    """, (client_id,)).fetchone()
    if not c:
        return jsonify({'error': 'Cliente não encontrado'}), 404

    appointments = conn.execute(
        "SELECT * FROM appointments WHERE client_id = ? ORDER BY appointment_date DESC, appointment_time DESC",
        (client_id,)
    ).fetchall()

    result = format_client(c)
    result['appointments'] = [dict(a) for a in appointments]
    return jsonify(result)


@clients_bp.route('/', methods=['POST'])
@validate_client
def create_client():
    data = request.get_json()
    conn = get_db()
    name = data['name']
    phone = data['phone']
    email = data.get('email', '')
    ini = data.get('avatar_initials') or ''.join(w[0] for w in name.split())[:2].upper()
    bg = data.get('avatar_bg', '#daeaf8')
    color = data.get('avatar_color', '#1a5fab')
    notes = data.get('notes', '')
    status = data.get('status', 'regular')

    cur = conn.execute(
        "INSERT INTO clients (name, phone, email, avatar_initials, avatar_bg, avatar_color, notes, status) VALUES (?,?,?,?,?,?,?,?)",
        (name, phone, email, ini, bg, color, notes, status)
    )
    conn.commit()

    c = conn.execute("SELECT * FROM clients WHERE id = ?", (cur.lastrowid,)).fetchone()
    return jsonify(format_client(dict(c) | {'visits': 0, 'total_spent': 0, 'last_visit': None})), 201


@clients_bp.route('/<int:client_id>', methods=['PUT'])
def update_client(client_id):
    conn = get_db()
    existing = conn.execute("SELECT * FROM clients WHERE id = ?", (client_id,)).fetchone()
    if not existing:
        return jsonify({'error': 'Cliente não encontrado'}), 404

    data = request.get_json()

    conn.execute("""
        UPDATE clients SET
            name = COALESCE(?, name),
            phone = COALESCE(?, phone),
            email = COALESCE(?, email),
            avatar_initials = COALESCE(?, avatar_initials),
            avatar_bg = COALESCE(?, avatar_bg),
            avatar_color = COALESCE(?, avatar_color),
            notes = COALESCE(?, notes),
            status = COALESCE(?, status),
            updated_at = datetime('now', 'localtime')
        WHERE id = ?
    """, (
        data.get('name'), data.get('phone'), data.get('email'),
        data.get('avatar_initials'), data.get('avatar_bg'), data.get('avatar_color'),
        data.get('notes'), data.get('status'),
        client_id
    ))
    conn.commit()

    c = conn.execute("""
        SELECT c.*,
            (SELECT COUNT(*) FROM appointments WHERE client_id = c.id) as visits,
            (SELECT COALESCE(SUM(price), 0) FROM appointments WHERE client_id = c.id) as total_spent,
            (SELECT MAX(appointment_date) FROM appointments WHERE client_id = c.id) as last_visit
        FROM clients c WHERE c.id = ?
    """, (client_id,)).fetchone()
    return jsonify(format_client(c))


@clients_bp.route('/<int:client_id>', methods=['DELETE'])
def delete_client(client_id):
    conn = get_db()
    existing = conn.execute("SELECT * FROM clients WHERE id = ?", (client_id,)).fetchone()
    if not existing:
        return jsonify({'error': 'Cliente não encontrado'}), 404
    conn.execute("DELETE FROM appointments WHERE client_id = ?", (client_id,))
    conn.execute("DELETE FROM clients WHERE id = ?", (client_id,))
    conn.commit()
    return jsonify({'message': 'Cliente removido', 'id': client_id})
