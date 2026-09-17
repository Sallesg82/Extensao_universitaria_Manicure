from flask import Blueprint, request, jsonify
from db.database import get_db, _run, TABLE_PRODUCTS
from ws import socketio

products_bp = Blueprint('products', __name__)

INITIAL_PRODUCTS = [
    {"name": "Esmalte Risqué Cremoso", "category": "esmaltes", "qty": 24, "price": 5.50, "missing": False, "min_qty": 10},
    {"name": "Gel Construtor Vòlia Classic", "category": "esmaltes", "qty": 6, "price": 65.0, "missing": False, "min_qty": 3},
    {"name": "Óleo Nutritivo de Cutícula", "category": "cuidados", "qty": 4, "price": 18.0, "missing": False, "min_qty": 5},
    {"name": "Luvas Nitrílicas Rosa (cx 100un)", "category": "descartaveis", "qty": 2, "price": 38.0, "missing": False, "min_qty": 4},
    {"name": "Algodão Hidrófilo Rolete", "category": "descartaveis", "qty": 0, "price": 8.50, "missing": True, "min_qty": 5},
    {"name": "Removedor Sem Acetona 500ml", "category": "quimicos", "qty": 8, "price": 16.0, "missing": False, "min_qty": 4},
    {"name": "Álcool Isopropílico 70% 1L", "category": "quimicos", "qty": 3, "price": 22.0, "missing": False, "min_qty": 3},
    {"name": "Alicate de Cutícula Mundial 777", "category": "equipamentos", "qty": 7, "price": 42.0, "missing": False, "min_qty": 3},
    {"name": "Lixas Bloco Fecha Poros (pct 10)", "category": "equipamentos", "qty": 0, "price": 14.0, "missing": True, "min_qty": 4},
    {"name": "Toalhas Descartáveis Manicure (pct 50)", "category": "descartaveis", "qty": 12, "price": 28.0, "missing": False, "min_qty": 5},
]

LEGACY_CATEGORY_MAP = {
    'pink': 'esmaltes',
    'amber': 'cuidados',
    'blue': 'descartaveis',
    'purple': 'quimicos'
}


def _normalize_category(cat: str) -> str:
    if not cat:
        return 'esmaltes'
    cat = str(cat).strip().lower()
    return LEGACY_CATEGORY_MAP.get(cat, cat)


def _ensure_products_table():
    """Garante existência da tabela de produtos e migra categorias antigas se necessário."""
    try:
        _run("""
            CREATE TABLE IF NOT EXISTS public.products (
                id SERIAL PRIMARY KEY,
                name TEXT NOT NULL,
                category TEXT DEFAULT 'esmaltes',
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
                get_db().table(TABLE_PRODUCTS).insert(p).execute()
        else:
            # Migração transparente de categorias legadas (pink, amber, blue, purple)
            for old_cat, new_cat in LEGACY_CATEGORY_MAP.items():
                _run(
                    "UPDATE public.products SET category = %s WHERE category = %s",
                    (new_cat, old_cat)
                )
    except Exception as e:
        print("[Estoque DB] Aviso ao verificar tabela products:", e)


def _first(table, column, value):
    r = get_db().table(table).select('*').eq(column, value).limit(1).execute()
    return r.data[0] if r.data else None


@products_bp.route('', methods=['GET'])
@products_bp.route('/', methods=['GET'])
def list_products():
    """Lista produtos com filtros opcionais de busca, categoria e situação."""
    _ensure_products_table()
    search = request.args.get('search', '').strip()
    category = request.args.get('category', '').strip()
    situation = request.args.get('situation', '').strip()  # 'todos', 'baixo', 'falta', 'ok'

    try:
        sql = "SELECT * FROM public.products WHERE 1=1"
        params = []

        if search:
            sql += " AND name ILIKE %s"
            params.append(f"%{search}%")

        if category and category != 'todos':
            sql += " AND category = %s"
            params.append(_normalize_category(category))

        if situation == 'falta':
            sql += " AND (missing = true OR qty = 0)"
        elif situation == 'baixo':
            sql += " AND (missing = false AND qty > 0 AND qty <= min_qty)"
        elif situation == 'ok':
            sql += " AND (missing = false AND qty > min_qty)"

        sql += " ORDER BY missing DESC, (qty <= min_qty) DESC, id ASC"

        rows = _run(sql, tuple(params))
        return jsonify([dict(r) for r in rows])
    except Exception as e:
        print("[Estoque] Erro ao listar produtos:", e)
        # Fallback usando supabase-like query builder
        result = get_db().table(TABLE_PRODUCTS).select('*').order('id').execute()
        return jsonify([dict(r) for r in result.data])


@products_bp.route('/stats', methods=['GET'])
def get_products_stats():
    """Retorna métricas em tempo real para os cartões KPI do Estoque."""
    _ensure_products_table()
    try:
        rows = _run("""
            SELECT 
                COUNT(*) as total_products,
                COALESCE(SUM(qty), 0) as total_units,
                COALESCE(SUM(qty * price), 0) as total_value,
                COALESCE(SUM(CASE WHEN (missing = true OR qty = 0) THEN 1 ELSE 0 END), 0) as out_of_stock_count,
                COALESCE(SUM(CASE WHEN (missing = false AND qty > 0 AND qty <= min_qty) THEN 1 ELSE 0 END), 0) as low_stock_count,
                COALESCE(SUM(CASE WHEN (missing = false AND qty > min_qty) THEN 1 ELSE 0 END), 0) as in_stock_count
            FROM public.products
        """)
        stats = dict(rows[0]) if rows else {
            'total_products': 0,
            'total_units': 0,
            'total_value': 0.0,
            'out_of_stock_count': 0,
            'low_stock_count': 0,
            'in_stock_count': 0
        }
        return jsonify(stats)
    except Exception as e:
        print("[Estoque] Erro ao calcular estatísticas:", e)
        return jsonify({'error': str(e)}), 500


@products_bp.route('/<int:prod_id>', methods=['GET'])
def get_product(prod_id):
    _ensure_products_table()
    prod = _first(TABLE_PRODUCTS, 'id', prod_id)
    if not prod:
        return jsonify({'error': 'Produto não encontrado'}), 404
    return jsonify(dict(prod))


@products_bp.route('', methods=['POST'])
@products_bp.route('/', methods=['POST'])
def create_product():
    """Cadastra um novo produto no estoque."""
    _ensure_products_table()
    data = request.get_json() or {}
    name = str(data.get('name', '')).strip()
    if not name:
        return jsonify({'error': 'Nome do produto é obrigatório'}), 400

    missing = bool(data.get('missing', False))
    qty = 0 if missing else max(0, int(data.get('qty', 0)))
    price = max(0.0, float(data.get('price', 0)))
    min_qty = max(0, int(data.get('min_qty', 5)))
    category = _normalize_category(data.get('category', 'esmaltes'))

    payload = {
        'name': name,
        'category': category,
        'qty': qty,
        'price': price,
        'min_qty': min_qty,
        'missing': missing,
    }

    result = get_db().table(TABLE_PRODUCTS).insert(payload).execute()
    prod = dict(result.data[0])

    socketio.emit('product:changed', {'action': 'created', 'product': prod})
    socketio.emit('data:changed', {'type': 'product', 'action': 'created', 'id': prod['id']})
    return jsonify(prod), 201


@products_bp.route('/<int:prod_id>', methods=['PUT'])
def update_product(prod_id):
    """Atualiza informações completas de um produto."""
    _ensure_products_table()
    existing = _first(TABLE_PRODUCTS, 'id', prod_id)
    if not existing:
        return jsonify({'error': 'Produto não encontrado'}), 404

    data = request.get_json() or {}
    update_data = {}

    if 'name' in data and data['name'] is not None:
        name = str(data['name']).strip()
        if not name:
            return jsonify({'error': 'Nome do produto não pode ser vazio'}), 400
        update_data['name'] = name

    if 'category' in data and data['category'] is not None:
        update_data['category'] = _normalize_category(data['category'])

    if 'price' in data and data['price'] is not None:
        update_data['price'] = max(0.0, float(data['price']))

    if 'min_qty' in data and data['min_qty'] is not None:
        update_data['min_qty'] = max(0, int(data['min_qty']))

    if 'missing' in data and data['missing'] is not None:
        missing = bool(data['missing'])
        update_data['missing'] = missing
        if missing:
            update_data['qty'] = 0

    if 'qty' in data and data['qty'] is not None and not update_data.get('missing'):
        qty = max(0, int(data['qty']))
        update_data['qty'] = qty
        if qty > 0 and 'missing' not in update_data:
            update_data['missing'] = False

    update_data['updated_at'] = 'NOW()'

    if update_data:
        get_db().table(TABLE_PRODUCTS).update(update_data).eq('id', prod_id).execute()

    prod = _first(TABLE_PRODUCTS, 'id', prod_id)
    result = dict(prod)

    socketio.emit('product:changed', {'action': 'updated', 'product': result})
    socketio.emit('data:changed', {'type': 'product', 'action': 'updated', 'id': prod_id})
    return jsonify(result)


@products_bp.route('/<int:prod_id>/stock', methods=['PATCH'])
def adjust_stock(prod_id):
    """
    Ajuste rápido de quantidade em estoque (+1, -1 ou quantidade absoluta).
    Recebe {'delta': 1} ou {'delta': -1} ou {'qty': 10}.
    """
    _ensure_products_table()
    existing = _first(TABLE_PRODUCTS, 'id', prod_id)
    if not existing:
        return jsonify({'error': 'Produto não encontrado'}), 404

    data = request.get_json() or {}
    curr_qty = int(existing.get('qty', 0))

    if 'delta' in data:
        delta = int(data['delta'])
        new_qty = max(0, curr_qty + delta)
    elif 'qty' in data:
        new_qty = max(0, int(data['qty']))
    else:
        return jsonify({'error': 'Parâmetro delta ou qty é obrigatório'}), 400

    new_missing = (new_qty == 0)

    _run(
        """
        UPDATE public.products 
        SET qty = %s, missing = %s, updated_at = NOW() 
        WHERE id = %s
        """,
        (new_qty, new_missing, prod_id)
    )

    prod = _first(TABLE_PRODUCTS, 'id', prod_id)
    result = dict(prod)

    socketio.emit('product:changed', {'action': 'updated', 'product': result})
    socketio.emit('data:changed', {'type': 'product', 'action': 'updated', 'id': prod_id})
    return jsonify(result)


@products_bp.route('/<int:prod_id>', methods=['DELETE'])
def delete_product(prod_id):
    """Exclui um produto do estoque."""
    _ensure_products_table()
    existing = _first(TABLE_PRODUCTS, 'id', prod_id)
    if not existing:
        return jsonify({'error': 'Produto não encontrado'}), 404

    get_db().table(TABLE_PRODUCTS).delete().eq('id', prod_id).execute()

    socketio.emit('product:changed', {'action': 'deleted', 'id': prod_id})
    socketio.emit('data:changed', {'type': 'product', 'action': 'deleted', 'id': prod_id})
    return jsonify({'message': 'Produto removido com sucesso', 'id': prod_id})
