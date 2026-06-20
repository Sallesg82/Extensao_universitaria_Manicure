from flask import Blueprint, request, jsonify
from db.database import get_db, all_clients, get_client, create_client, update_client, delete_client
from middleware.validation import validate_client
from ws import socketio
import re

clients_bp = Blueprint('clients', __name__)


def format_client(c):
    return {
        'id': c['id'],
        'name': c['name'],
        'phone': c['phone'],
        'email': c['email'],
        'cpf': c.get('cpf') or '',
        'avatar_initials': c['avatar_initials'],
        'avatar_bg': c['avatar_bg'],
        'avatar_color': c['avatar_color'],
        'notes': c['notes'],
        'status': c['status'],
        'visits': c.get('visits') or 0,
        'total_spent': c.get('total_spent') or 0,
        'last_visit': c.get('last_visit'),
        'created_at': c.get('created_at'),
        'updated_at': c.get('updated_at'),
    }


@clients_bp.route('/', methods=['GET'])
def list_clients():
    search = request.args.get('search', '').strip().lower()
    status = request.args.get('status', '').strip().lower()
    clients = all_clients()
    if status:
        clients = [c for c in clients if c.get('status', '').lower() == status]
    if search:
        search_clean = re.sub(r'\D', '', search)
        clients = [c for c in clients if search in c.get('name', '').lower() or (search_clean and search_clean in re.sub(r'\D', '', c.get('phone', '')))]
    return jsonify([format_client(c) for c in clients])


@clients_bp.route('/<int:client_id>', methods=['GET'])
def get_client_by_id(client_id):
    try:
        c = get_client(client_id)
    except Exception:
        return jsonify({'error': 'Cliente n\u00e3o encontrado'}), 404
    result = format_client(c)
    result['appointments'] = c.get('appointments', [])
    result['service_usage'] = c.get('service_usage', [])
    return jsonify(result)


@clients_bp.route('/', methods=['POST'])
@validate_client
def create_client_route():
    data = request.get_json()
    c = create_client(
        name=data['name'], phone=data['phone'],
        email=data.get('email', ''),
        cpf=data.get('cpf', ''),
        avatar_initials=data.get('avatar_initials', ''),
        avatar_bg=data.get('avatar_bg', '#daeaf8'),
        avatar_color=data.get('avatar_color', '#1a5fab'),
        notes=data.get('notes', ''),
        status=data.get('status', 'regular'),
    )
    c['visits'] = 0
    c['total_spent'] = 0
    c['last_visit'] = None
    result = format_client(c)
    socketio.emit('client:created', result)
    socketio.emit('data:changed', {'type': 'client', 'action': 'created'})
    return jsonify(result), 201


@clients_bp.route('/<int:client_id>', methods=['PUT'])
def update_client_route(client_id):
    data = request.get_json()
    try:
        c = update_client(client_id, data)
    except Exception:
        return jsonify({'error': 'Cliente n\u00e3o encontrado'}), 404
    result = format_client(c)
    socketio.emit('client:updated', result)
    socketio.emit('data:changed', {'type': 'client', 'action': 'updated'})
    return jsonify(result)


@clients_bp.route('/<int:client_id>', methods=['DELETE'])
def delete_client_route(client_id):
    try:
        delete_client(client_id)
    except Exception:
        return jsonify({'error': 'Cliente n\u00e3o encontrado'}), 404
    socketio.emit('client:deleted', {'id': client_id})
    socketio.emit('data:changed', {'type': 'client', 'action': 'deleted'})
    return jsonify({'message': 'Cliente removido', 'id': client_id})
