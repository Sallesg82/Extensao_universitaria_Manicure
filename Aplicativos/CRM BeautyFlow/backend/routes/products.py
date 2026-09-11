from flask import Blueprint, request, jsonify
from db.database import get_db, _run
from ws import socketio

products_bp = Blueprint('products', __name__)

INITIAL_PRODUCTS = [
    {"name": "Esmalte OPI", "category": "pink", "qty": 12, "price": 8.0, "missing": False, "min_qty": 5},
    {"name": "Óleo de Cutícula", "category": "amber", "qty": 2, "price": 15.0, "missing": False, "min_qty": 5},
    {"name": "Luvas Descartáveis (cx)", "category": "blue", "qty": 3, "price": 25.0, "missing": False, "min_qty": 2},
    {"name": "Algodão", "category": "pink", "qty": 0, "price": 4.0, "missing": True, "min_qty": 8},
    {"name": "Removedor de Esmalte", "category": "purple", "qty": 5, "price": 12.0, "missing": False, "min_qty": 3},
    {"name": "Cera Depilatória", "category": "amber", "qty": 0, "price": 45.0, "missing": True, "min_qty": 2},
    {"name": "Henna para Sobrancelha", "category": "amber", "qty": 2, "price": 20.0, "missing": False, "min_qty": 4},
    {"name": "Toalhas Descartáveis", "category": "blue", "qty": 8, "price": 18.0, "missing": False, "min_qty": 4},
    {"name": "Álcool 70%", "category": "purple", "qty": 6, "price": 10.0, "missing": False, "min_qty": 3},
    {"name": "Palito de Laranjeira", "category": "pink", "qty": 15, "price": 3.0, "missing": False, "min_qty": 6},
]

def _ensure_products_table():
    try:
        _run("""
            CREATE TABLE IF NOT EXISTS public.products (
                id SERIAL PRIMARY KEY,
                name TEXT NOT NULL,
                category TEXT DEFAULT 'pink',
                qty INTEGER DEFAULT 0,
                price REAL DEFAULT 0,
                min_qty INTEGER DEFAULT 5,
                missing BOOLEAN DEFAULT false,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
            );
        """)
        rows = _run("SELECT COUNT(*) as count FROM public.products")
        if rows and rows[0]['count'] == 0:
            for p in INITIAL_PRODUCTS:
                get_db().table('products').insert(p).execute()
    except Exception as e:
        print("Warning: _ensure_products_table error:", e)

def _first(table, column, value):
    r = get_db().table(table).select('*').eq(column, value).limit(1).execute()
    return r.data[0] if r.data else None


@products_bp.route('', methods=['GET'])
@products_bp.route('/', methods=['GET'])
def list_products():
    _ensure_products_table()
    result = get_db().table('products').select('*').order('name').execute()
    return jsonify([dict(r) for r in result.data])


@products_bp.route('', methods=['POST'])
@products_bp.route('/', methods=['POST'])
def create_product():
    _ensure_products_table()
    data = request.get_json() or {}
    if not data.get('name'):
        return jsonify({'error': 'Nome do produto é obrigatório'}), 400

    payload = {
        'name': str(data['name']).strip(),
        'category': data.get('category', 'pink'),
        'qty': int(data.get('qty', 0)),
        'price': float(data.get('price', 0)),
        'min_qty': int(data.get('min_qty', 5)),
        'missing': bool(data.get('missing', False)),
    }

    result = get_db().table('products').insert(payload).execute()
    prod = dict(result.data[0])
    socketio.emit('product:changed', {'action': 'created', 'product': prod})
    socketio.emit('data:changed', {'type': 'product', 'action': 'created'})
    return jsonify(prod), 201


@products_bp.route('/<int:prod_id>', methods=['PUT'])
def update_product(prod_id):
    _ensure_products_table()
    existing = _first('products', 'id', prod_id)
    if not existing:
        return jsonify({'error': 'Produto não encontrado'}), 404

    data = request.get_json() or {}
    update_data = {}
    if 'name' in data and data['name'] is not None:
        update_data['name'] = str(data['name']).strip()
    if 'category' in data and data['category'] is not None:
        update_data['category'] = str(data['category'])
    if 'qty' in data and data['qty'] is not None:
        update_data['qty'] = int(data['qty'])
    if 'price' in data and data['price'] is not None:
        update_data['price'] = float(data['price'])
    if 'min_qty' in data and data['min_qty'] is not None:
        update_data['min_qty'] = int(data['min_qty'])
    if 'missing' in data and data['missing'] is not None:
        update_data['missing'] = bool(data['missing'])
        if update_data['missing']:
            update_data['qty'] = 0

    if update_data:
        get_db().table('products').update(update_data).eq('id', prod_id).execute()

    prod = _first('products', 'id', prod_id)
    result = dict(prod)
    socketio.emit('product:changed', {'action': 'updated', 'product': result})
    socketio.emit('data:changed', {'type': 'product', 'action': 'updated'})
    return jsonify(result)


@products_bp.route('/<int:prod_id>', methods=['DELETE'])
def delete_product(prod_id):
    _ensure_products_table()
    existing = _first('products', 'id', prod_id)
    if not existing:
        return jsonify({'error': 'Produto não encontrado'}), 404
    get_db().table('products').delete().eq('id', prod_id).execute()
    socketio.emit('product:changed', {'action': 'deleted', 'id': prod_id})
    socketio.emit('data:changed', {'type': 'product', 'action': 'deleted'})
    return jsonify({'message': 'Produto removido', 'id': prod_id})
