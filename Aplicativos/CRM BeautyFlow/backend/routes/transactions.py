from flask import Blueprint, request, jsonify
from db.database import get_db, _insert_transaction
from ws import socketio

transactions_bp = Blueprint('transactions', __name__)


@transactions_bp.route('/', methods=['GET'])
def list_transactions():
    date_from = request.args.get('date_from', '')
    date_to = request.args.get('date_to', '')
    tx_type = request.args.get('type', '')
    limit = min(request.args.get('limit', 200, type=int), 1000)
    supabase = get_db()
    query = supabase.table('transactions').select('*').order('date', desc=True).order('id', desc=True)
    if date_from:
        query = query.gte('date', date_from)
    if date_to:
        query = query.lte('date', date_to)
    if tx_type:
        query = query.eq('type', tx_type)
    result = query.limit(limit).execute()
    return jsonify(result.data)


@transactions_bp.route('/', methods=['POST'])
def create_transaction():
    data = request.get_json()
    required = ['type', 'amount', 'date', 'description']
    missing = [f for f in required if f not in data]
    if missing:
        return jsonify({'error': f'Campos obrigatórios: {", ".join(missing)}'}), 400
    if data['type'] not in ('income', 'expense'):
        return jsonify({'error': 'Tipo deve ser income ou expense'}), 400
    payload = {
        'type': data['type'],
        'amount': float(data['amount']),
        'date': data['date'],
        'description': data.get('description', ''),
        'category': data.get('category', ''),
        'payment_method': data.get('payment_method', ''),
        'appointment_id': data.get('appointment_id'),
        'client_id': data.get('client_id'),
        'client_name': data.get('client_name', ''),
        'service': data.get('service', ''),
    }
    result = _insert_transaction(payload)
    tx = result.data[0]
    socketio.emit('transaction:created', tx)
    socketio.emit('data:changed', {'type': 'transaction', 'action': 'created'})
    return jsonify(tx), 201


@transactions_bp.route('/<int:tx_id>', methods=['GET'])
def get_transaction(tx_id):
    supabase = get_db()
    result = supabase.table('transactions').select('*').eq('id', tx_id).limit(1).execute()
    if not result.data:
        return jsonify({'error': 'Transação não encontrada'}), 404
    return jsonify(result.data[0])


@transactions_bp.route('/<int:tx_id>', methods=['PUT'])
def update_transaction(tx_id):
    supabase = get_db()
    existing = supabase.table('transactions').select('*').eq('id', tx_id).limit(1).execute()
    if not existing.data:
        return jsonify({'error': 'Transação não encontrada'}), 404
    data = request.get_json()
    update_data = {}
    for field in ['type', 'amount', 'date', 'description', 'category', 'payment_method']:
        if field in data:
            update_data[field] = data[field]
    if 'amount' in update_data:
        update_data['amount'] = float(update_data['amount'])
    if update_data:
        supabase.table('transactions').update(update_data).eq('id', tx_id).execute()
    result = supabase.table('transactions').select('*').eq('id', tx_id).limit(1).execute()
    socketio.emit('transaction:updated', result.data[0])
    socketio.emit('data:changed', {'type': 'transaction', 'action': 'updated'})
    return jsonify(result.data[0])


@transactions_bp.route('/<int:tx_id>', methods=['DELETE'])
def delete_transaction(tx_id):
    supabase = get_db()
    existing = supabase.table('transactions').select('id').eq('id', tx_id).limit(1).execute()
    if not existing.data:
        return jsonify({'error': 'Transação não encontrada'}), 404
    supabase.table('transactions').delete().eq('id', tx_id).execute()
    socketio.emit('transaction:deleted', {'id': tx_id})
    socketio.emit('data:changed', {'type': 'transaction', 'action': 'deleted'})
    return jsonify({'message': 'Transação removida', 'id': tx_id})
