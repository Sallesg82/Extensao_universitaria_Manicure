from functools import wraps
from flask import request, jsonify


def validate_client(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        data = request.get_json(silent=True) or {}
        errors = []
        if not data.get('name') or len(str(data['name']).strip()) < 2:
            errors.append('Nome deve ter pelo menos 2 caracteres')
        if not data.get('phone') or len(str(data['phone']).strip()) < 8:
            errors.append('Telefone inválido')
        if errors:
            return jsonify({'error': 'Dados inválidos', 'details': errors}), 400
        return f(*args, **kwargs)
    return wrapper


def validate_appointment(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        data = request.get_json(silent=True) or {}
        errors = []
        if not data.get('client_id'):
            errors.append('ID do cliente é obrigatório')
        if not data.get('service') or len(str(data['service']).strip()) < 2:
            errors.append('Nome do serviço é obrigatório')
        import re
        if not data.get('appointment_date') or not re.match(r'^\d{4}-\d{2}-\d{2}$', str(data['appointment_date'])):
            errors.append('Data deve estar no formato YYYY-MM-DD')
        if not data.get('appointment_time') or not re.match(r'^\d{2}:\d{2}$', str(data['appointment_time'])):
            errors.append('Hora deve estar no formato HH:MM')
        price = data.get('price')
        if price is None:
            errors.append('Preço é obrigatório')
        else:
            try:
                if float(price) < 0:
                    errors.append('Preço deve ser positivo')
            except (ValueError, TypeError):
                errors.append('Preço deve ser um número')
        if errors:
            return jsonify({'error': 'Dados inválidos', 'details': errors}), 400
        return f(*args, **kwargs)
    return wrapper
