from flask import Blueprint, request, jsonify
from db.database import get_db

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
        'color': data.get('color', '#4a90d9'),
    }).execute()
    return jsonify(dict(result.data[0])), 201


@services_bp.route('/<int:svc_id>', methods=['PUT'])
def update_service(svc_id):
    existing = _first('services', 'id', svc_id)
    if not existing:
        return jsonify({'error': 'Serviço não encontrado'}), 404

    data = request.get_json()
    update_data = {}
    for field in ['name', 'duration', 'color']:
        if field in data and data[field] is not None:
            update_data[field] = data[field]
    if 'price' in data and data['price'] is not None:
        update_data['price'] = float(data['price'])
    if update_data:
        get_db().table('services').update(update_data).eq('id', svc_id).execute()

    svc = _first('services', 'id', svc_id)
    return jsonify(dict(svc))


@services_bp.route('/<int:svc_id>', methods=['DELETE'])
def delete_service(svc_id):
    existing = _first('services', 'id', svc_id)
    if not existing:
        return jsonify({'error': 'Serviço não encontrado'}), 404
    get_db().table('services').delete().eq('id', svc_id).execute()
    return jsonify({'message': 'Serviço removido', 'id': svc_id})
