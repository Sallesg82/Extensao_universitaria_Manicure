import re
from datetime import datetime
from flask import Blueprint, request, jsonify
from db.database import get_meta, set_meta, get_all_metas
from ws import socketio

metas_bp = Blueprint('metas', __name__)

_MES_REGEX = re.compile(r'^\d{4}-(0[1-9]|1[0-2])$')


def _format_mes(data, mes_arg=None):
    if mes_arg and _MES_REGEX.match(mes_arg):
        return mes_arg
    mes = data.get('mes')
    if mes and _MES_REGEX.match(str(mes).strip()):
        return str(mes).strip()
    month = data.get('month')
    year = data.get('year')
    if month and year:
        try:
            m = int(month)
            y = int(year)
            if 1 <= m <= 12 and 2000 <= y <= 2100:
                return f"{y:04d}-{m:02d}"
        except (ValueError, TypeError):
            pass
    now = datetime.now()
    return f"{now.year:04d}-{now.month:02d}"


@metas_bp.route('', methods=['GET'])
@metas_bp.route('/', methods=['GET'])
def list_or_get_meta():
    mes = request.args.get('mes')
    month = request.args.get('month', type=int)
    year = request.args.get('year', type=int)
    if mes and _MES_REGEX.match(mes):
        return jsonify({'mes': mes, 'meta': get_meta(mes)})
    if month and year and 1 <= month <= 12:
        mes_formatted = f"{year:04d}-{month:02d}"
        return jsonify({'mes': mes_formatted, 'meta': get_meta(mes_formatted)})
    all_metas = get_all_metas()
    return jsonify(all_metas)


@metas_bp.route('/<mes>', methods=['GET'])
def get_single_meta(mes):
    if not _MES_REGEX.match(mes):
        return jsonify({'error': 'Formato de mês inválido. Use YYYY-MM'}), 400
    return jsonify({'mes': mes, 'meta': get_meta(mes)})


@metas_bp.route('', methods=['POST', 'PUT'])
@metas_bp.route('/', methods=['POST', 'PUT'])
@metas_bp.route('/<mes>', methods=['POST', 'PUT'])
def save_meta(mes=None):
    data = request.get_json(silent=True) or {}
    mes_target = _format_mes(data, mes)
    
    raw_val = data.get('meta')
    if raw_val is None:
        raw_val = data.get('meta_mensal')
    if raw_val is None:
        return jsonify({'error': 'Valor da meta é obrigatório'}), 400
    
    try:
        val = float(raw_val)
        if val <= 0:
            return jsonify({'error': 'A meta deve ser maior que zero'}), 400
    except (ValueError, TypeError):
        return jsonify({'error': 'Valor da meta inválido'}), 400

    saved = set_meta(mes_target, val)
    
    # Notifica via WebSocket para atualização em tempo real
    try:
        socketio.emit('data:changed', {
            'type': 'meta',
            'mes': mes_target,
            'meta': val
        })
    except Exception:
        pass

    return jsonify({
        'success': True,
        'mes': mes_target,
        'meta': val,
        'data': saved
    })
