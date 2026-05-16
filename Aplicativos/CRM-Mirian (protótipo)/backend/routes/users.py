from flask import Blueprint, request, jsonify
from werkzeug.security import generate_password_hash, check_password_hash
from db.database import all_users, get_user, get_user_by_email, create_user, update_user, delete_user

users_bp = Blueprint('users', __name__)


@users_bp.route('/', methods=['GET'])
def list_users():
    return jsonify(all_users())


@users_bp.route('/exists', methods=['GET'])
def users_exist():
    return jsonify({'exists': len(all_users()) > 0})


@users_bp.route('/<int:user_id>', methods=['GET'])
def get_user_route(user_id):
    u = get_user(user_id)
    if not u:
        return jsonify({'error': 'Usuário não encontrado'}), 404
    u.pop('password_hash', None)
    return jsonify(u)


@users_bp.route('/', methods=['POST'])
def create_user_route():
    data = request.get_json()
    if not data.get('name') or not data.get('email') or not data.get('password'):
        return jsonify({'error': 'Nome, email e senha são obrigatórios'}), 400
    if get_user_by_email(data['email']):
        return jsonify({'error': 'Email já cadastrado'}), 409
    pw_hash = generate_password_hash(data['password'])
    u = create_user(
        name=data['name'],
        email=data['email'],
        password_hash=pw_hash,
        phone=data.get('phone', ''),
        role=data.get('role', 'admin'),
    )
    if u:
        u.pop('password_hash', None)
    return jsonify(u), 201


@users_bp.route('/<int:user_id>', methods=['PUT'])
def update_user_route(user_id):
    existing = get_user(user_id)
    if not existing:
        return jsonify({'error': 'Usuário não encontrado'}), 404
    data = request.get_json()
    update_data = {}
    if 'name' in data:
        update_data['name'] = data['name']
    if 'email' in data:
        if data['email'] != existing['email'] and get_user_by_email(data['email']):
            return jsonify({'error': 'Email já cadastrado'}), 409
        update_data['email'] = data['email']
    if 'phone' in data:
        update_data['phone'] = data['phone']
    if 'role' in data:
        update_data['role'] = data['role']
    if 'password' in data and data['password']:
        update_data['password_hash'] = generate_password_hash(data['password'])
    if update_data:
        u = update_user(user_id, update_data)
    else:
        u = get_user(user_id)
    if u:
        u.pop('password_hash', None)
    return jsonify(u)


@users_bp.route('/<int:user_id>', methods=['DELETE'])
def delete_user_route(user_id):
    existing = get_user(user_id)
    if not existing:
        return jsonify({'error': 'Usuário não encontrado'}), 404
    delete_user(user_id)
    return jsonify({'message': 'Usuário removido', 'id': user_id})


@users_bp.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    if not data.get('email') or not data.get('password'):
        return jsonify({'error': 'Email e senha são obrigatórios'}), 400
    u = get_user_by_email(data['email'])
    if not u or not check_password_hash(u['password_hash'], data['password']):
        return jsonify({'error': 'Email ou senha inválidos'}), 401
    u.pop('password_hash', None)
    return jsonify(u)
