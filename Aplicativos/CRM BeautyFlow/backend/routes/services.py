from flask import Blueprint, request, jsonify
from db.database import get_db
from ws import socketio

services_bp = Blueprint('services', __name__)


def _first(table, column, value):
    r = get_db().table(table).select('*').eq(column, value).limit(1).execute()
    return r.data[0] if r.data else None


@services_bp.route('/', methods=['GET'])
def list_services():
    result = get_db().table('services').select('*').order('name').execute()
    return jsonify([dict(r) for r in result.data])


@services_bp.route('/', methods=['POST'])
def create_service():
    data = request.get_json()
    if not data.get('name') or not data.get('duration') or data.get('price') is None:
        return jsonify({'error': 'Nome, duração e preço são obrigatórios'}), 400

    existing = _first('services', 'name', data['name'])
    if existing:
        return jsonify(dict(existing)), 200

    result = get_db().table('services').insert({
        'name': data['name'],
        'duration': data['duration'],
        'price': float(data['price']),
        'buffer': data.get('buffer', 15),
        'color': data.get('color', '#4a90d9'),
    }).execute()
    svc = dict(result.data[0])
    socketio.emit('service:changed', {'action': 'created', 'service': svc})
    socketio.emit('data:changed', {'type': 'service', 'action': 'created'})
    return jsonify(svc), 201


@services_bp.route('/<int:svc_id>', methods=['PUT'])
def update_service(svc_id):
    existing = _first('services', 'id', svc_id)
    if not existing:
        return jsonify({'error': 'Serviço não encontrado'}), 404

    data = request.get_json()
    update_data = {}
    for field in ['name', 'duration', 'buffer', 'color']:
        if field in data and data[field] is not None:
            update_data[field] = data[field]
    if 'price' in data and data['price'] is not None:
        update_data['price'] = float(data['price'])
    if update_data:
        get_db().table('services').update(update_data).eq('id', svc_id).execute()

    svc = _first('services', 'id', svc_id)
    result = dict(svc)
    socketio.emit('service:changed', {'action': 'updated', 'service': result})
    socketio.emit('data:changed', {'type': 'service', 'action': 'updated'})
    return jsonify(result)


@services_bp.route('/<int:svc_id>', methods=['DELETE'])
def delete_service(svc_id):
    existing = _first('services', 'id', svc_id)
    if not existing:
        return jsonify({'error': 'Serviço não encontrado'}), 404
    get_db().table('services').delete().eq('id', svc_id).execute()
    socketio.emit('service:changed', {'action': 'deleted', 'id': svc_id})
    socketio.emit('data:changed', {'type': 'service', 'action': 'deleted'})
    return jsonify({'message': 'Serviço removido', 'id': svc_id})
