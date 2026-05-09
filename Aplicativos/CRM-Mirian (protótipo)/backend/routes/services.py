from flask import Blueprint, request, jsonify
from db.database import get_db

services_bp = Blueprint('services', __name__)


@services_bp.route('/', methods=['GET'])
def list_services():
    conn = get_db()
    rows = conn.execute("SELECT * FROM services ORDER BY name ASC").fetchall()
    return jsonify([dict(r) for r in rows])


@services_bp.route('/', methods=['POST'])
def create_service():
    data = request.get_json()
    if not data.get('name') or not data.get('duration') or data.get('price') is None:
        return jsonify({'error': 'Nome, duração e preço são obrigatórios'}), 400
    conn = get_db()
    try:
        existing = conn.execute("SELECT * FROM services WHERE name = ?", (data['name'],)).fetchone()
        if existing:
            return jsonify(dict(existing)), 200
        cur = conn.execute(
            "INSERT INTO services (name, duration, price, color) VALUES (?,?,?,?)",
            (data['name'], data['duration'], float(data['price']), data.get('color', '#4a90d9'))
        )
        conn.commit()
        svc = conn.execute("SELECT * FROM services WHERE id = ?", (cur.lastrowid,)).fetchone()
        return jsonify(dict(svc)), 201
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


@services_bp.route('/<int:svc_id>', methods=['PUT'])
def update_service(svc_id):
    conn = get_db()
    existing = conn.execute("SELECT * FROM services WHERE id = ?", (svc_id,)).fetchone()
    if not existing:
        return jsonify({'error': 'Serviço não encontrado'}), 404
    data = request.get_json()
    conn.execute("""
        UPDATE services SET name = COALESCE(?, name), duration = COALESCE(?, duration),
            price = COALESCE(?, price), color = COALESCE(?, color) WHERE id = ?
    """, (data.get('name'), data.get('duration'),
          float(data['price']) if data.get('price') is not None else None,
          data.get('color'), svc_id))
    conn.commit()
    svc = conn.execute("SELECT * FROM services WHERE id = ?", (svc_id,)).fetchone()
    return jsonify(dict(svc))


@services_bp.route('/<int:svc_id>', methods=['DELETE'])
def delete_service(svc_id):
    conn = get_db()
    existing = conn.execute("SELECT * FROM services WHERE id = ?", (svc_id,)).fetchone()
    if not existing:
        return jsonify({'error': 'Serviço não encontrado'}), 404
    conn.execute("DELETE FROM services WHERE id = ?", (svc_id,))
    conn.commit()
    return jsonify({'message': 'Serviço removido', 'id': svc_id})
