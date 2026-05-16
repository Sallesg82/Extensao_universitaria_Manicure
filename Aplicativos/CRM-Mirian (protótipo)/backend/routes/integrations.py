from flask import Blueprint, request, jsonify
from db.database import list_integrations, get_integration, create_integration, update_integration, delete_integration

integrations_bp = Blueprint('integrations', __name__)


@integrations_bp.route('/', methods=['GET'])
def index():
    return jsonify(list_integrations())


@integrations_bp.route('/', methods=['POST'])
def create():
    data = request.get_json(silent=True) or {}
    name = (data.get('name') or '').strip()
    integ_type = (data.get('type') or '').strip()
    if not name:
        return jsonify({'error': 'Nome é obrigatório'}), 400
    if integ_type not in ('webhook', 'n8n', 'google_calendar'):
        return jsonify({'error': 'Tipo inválido'}), 400
    config = data.get('config', {})
    enabled = data.get('enabled', True)
    integ = create_integration(name, integ_type, config, enabled)
    if not integ:
        return jsonify({'error': 'Erro ao criar integração'}), 500
    return jsonify(integ), 201


@integrations_bp.route('/<int:integ_id>', methods=['GET'])
def get(integ_id):
    integ = get_integration(integ_id)
    if not integ:
        return jsonify({'error': 'Integração não encontrada'}), 404
    return jsonify(integ)


@integrations_bp.route('/<int:integ_id>', methods=['PUT'])
def update(integ_id):
    integ = get_integration(integ_id)
    if not integ:
        return jsonify({'error': 'Integração não encontrada'}), 404
    data = request.get_json(silent=True) or {}
    update_data = {}
    if 'name' in data:
        update_data['name'] = str(data['name']).strip()
    if 'config' in data:
        update_data['config'] = data['config']
    if 'enabled' in data:
        update_data['enabled'] = bool(data['enabled'])
    if not update_data:
        return jsonify({'error': 'Nenhum dado para atualizar'}), 400
    updated = update_integration(integ_id, update_data)
    if not updated:
        return jsonify({'error': 'Erro ao atualizar integração'}), 500
    return jsonify(updated)


@integrations_bp.route('/<int:integ_id>', methods=['DELETE'])
def delete(integ_id):
    integ = get_integration(integ_id)
    if not integ:
        return jsonify({'error': 'Integração não encontrada'}), 404
    delete_integration(integ_id)
    return jsonify({'message': 'Integração removida', 'id': integ_id})
