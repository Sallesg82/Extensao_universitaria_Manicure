import os
from flask import Flask, jsonify, send_from_directory
from flask_cors import CORS
from db.database import get_db
from routes.clients import clients_bp
from routes.appointments import appointments_bp
from routes.services import services_bp

STATIC_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'src')

app = Flask(__name__, static_folder=None)
CORS(app)

app.register_blueprint(clients_bp, url_prefix='/api/clients')
app.register_blueprint(appointments_bp, url_prefix='/api/appointments')
app.register_blueprint(services_bp, url_prefix='/api/services')


@app.route('/')
def index():
    return send_from_directory(STATIC_DIR, 'index.html')


@app.route('/css/<path:filename>')
def css(filename):
    return send_from_directory(os.path.join(STATIC_DIR, 'css'), filename)


@app.route('/js/<path:filename>')
def js(filename):
    return send_from_directory(os.path.join(STATIC_DIR, 'js'), filename)


@app.route('/api/stats')
def stats():
    conn = get_db()

    today_revenue = conn.execute("""
        SELECT COALESCE(SUM(price), 0) as total FROM appointments
        WHERE appointment_date = date('now', 'localtime') AND status != 'cancelled'
    """).fetchone()['total']

    today_count = conn.execute("""
        SELECT COUNT(*) as c FROM appointments WHERE appointment_date = date('now', 'localtime')
    """).fetchone()['c']

    today_pending = conn.execute("""
        SELECT COUNT(*) as c FROM appointments WHERE appointment_date = date('now', 'localtime') AND status = 'pending'
    """).fetchone()['c']

    active_clients = conn.execute("SELECT COUNT(*) as c FROM clients").fetchone()['c']

    avg_ticket = conn.execute("""
        SELECT COALESCE(AVG(price), 0) as avg FROM appointments WHERE status != 'cancelled'
    """).fetchone()['avg']

    month_revenue = conn.execute("""
        SELECT COALESCE(SUM(price), 0) as total FROM appointments
        WHERE strftime('%Y-%m', appointment_date) = strftime('%Y-%m', 'now', 'localtime')
        AND status != 'cancelled'
    """).fetchone()['total']

    month_expenses = conn.execute("""
        SELECT COALESCE(SUM(amount), 0) as total FROM transactions
        WHERE type = 'expense' AND strftime('%Y-%m', date) = strftime('%Y-%m', 'now', 'localtime')
    """).fetchone()['total']

    month_appointments = conn.execute("""
        SELECT a.appointment_date, a.price, a.service, a.status
        FROM appointments a
        WHERE strftime('%Y-%m', a.appointment_date) = strftime('%Y-%m', 'now', 'localtime')
        ORDER BY a.appointment_date ASC
    """).fetchall()

    month_transactions = conn.execute("""
        SELECT type, amount, date FROM transactions
        WHERE strftime('%Y-%m', date) = strftime('%Y-%m', 'now', 'localtime')
        ORDER BY date ASC
    """).fetchall()

    month_clients_count = conn.execute("""
        SELECT COUNT(DISTINCT client_id) as c FROM appointments
        WHERE strftime('%Y-%m', appointment_date) = strftime('%Y-%m', 'now', 'localtime')
    """).fetchone()['c']

    total_revenue_all = conn.execute("""
        SELECT COALESCE(SUM(price), 0) as total FROM appointments WHERE status != 'cancelled'
    """).fetchone()['total']

    meta_mensal = 7000
    meta_pct = round((month_revenue / meta_mensal) * 100, 1) if meta_mensal > 0 else 0

    top_clients = conn.execute("""
        SELECT c.id, c.name, c.avatar_initials, c.avatar_bg, c.avatar_color,
            COUNT(a.id) as visits,
            COALESCE(SUM(a.price), 0) as total_spent,
            MAX(a.appointment_date) as last_visit
        FROM clients c
        JOIN appointments a ON a.client_id = c.id
        GROUP BY c.id
        ORDER BY total_spent DESC
        LIMIT 5
    """).fetchall()

    today_appointments = conn.execute("""
        SELECT a.*, c.name as client_name, c.phone as client_phone
        FROM appointments a JOIN clients c ON c.id = a.client_id
        WHERE a.appointment_date = date('now', 'localtime')
        ORDER BY a.appointment_time ASC
    """).fetchall()

    weekly_revenue = []
    for row in month_appointments:
        d = row['appointment_date']
        price = row['price']
        if row['status'] == 'cancelled':
            continue
        try:
            dt = __import__('datetime').datetime.strptime(d, '%Y-%m-%d')
            week_num = (dt.day - 1) // 7
            while len(weekly_revenue) <= week_num:
                weekly_revenue.append(0)
            weekly_revenue[week_num] += price
        except (ValueError, TypeError):
            pass

    service_counts = {}
    service_revenue = {}
    for row in month_appointments:
        svc = row['service']
        if row['status'] != 'cancelled':
            service_counts[svc] = service_counts.get(svc, 0) + 1
            service_revenue[svc] = service_revenue.get(svc, 0) + row['price']
    total_services = sum(service_counts.values()) or 1
    total_svc_revenue = sum(service_revenue.values()) or 1
    service_breakdown = [
        {'name': k, 'count': v, 'pct': round(v / total_services * 100, 1)}
        for k, v in sorted(service_counts.items(), key=lambda x: -x[1])
    ][:5]
    service_revenue_breakdown = [
        {'name': k, 'revenue': v, 'pct': round(v / total_svc_revenue * 100, 1)}
        for k, v in sorted(service_revenue.items(), key=lambda x: -x[1])
    ][:5]

    pix_pending = conn.execute("""
        SELECT COUNT(*) as c FROM transactions
        WHERE type = 'income' AND payment_method = 'Pix'
        AND strftime('%Y-%m', date) = strftime('%Y-%m', 'now', 'localtime')
    """).fetchone()['c']

    recent_transactions = conn.execute("""
        SELECT t.*, c.name as client_name
        FROM transactions t
        LEFT JOIN appointments a ON a.id = t.appointment_id
        LEFT JOIN clients c ON c.id = a.client_id
        WHERE strftime('%Y-%m', t.date) = strftime('%Y-%m', 'now', 'localtime')
        ORDER BY t.date DESC, t.id DESC
        LIMIT 10
    """).fetchall()

    expenses_by_cat = conn.execute("""
        SELECT category, COALESCE(SUM(amount), 0) as total
        FROM transactions
        WHERE type = 'expense' AND strftime('%Y-%m', date) = strftime('%Y-%m', 'now', 'localtime')
        GROUP BY category
        ORDER BY total DESC
    """).fetchall()
    total_exp = sum(r['total'] for r in expenses_by_cat) or 1
    expenses_by_category = [
        {'category': r['category'] or 'Outros', 'amount': r['total'], 'pct': round(r['total'] / total_exp * 100, 1)}
        for r in expenses_by_cat
    ]

    day_names_pt = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb']
    daily_rev = {}
    daily_exp = {}
    for row in month_appointments:
        if row['status'] == 'cancelled':
            continue
        daily_rev[row['appointment_date']] = daily_rev.get(row['appointment_date'], 0) + row['price']
    for row in month_transactions:
        d = row['date']
        if row['type'] == 'expense':
            daily_exp[d] = daily_exp.get(d, 0) + row['amount']
        else:
            daily_rev[d] = daily_rev.get(d, 0) + row['amount']
    all_days = sorted(set(list(daily_rev.keys()) + list(daily_exp.keys())))
    daily_breakdown = []
    for d in all_days:
        try:
            dt = __import__('datetime').datetime.strptime(d, '%Y-%m-%d')
            day_label = day_names_pt[dt.weekday()]
        except (ValueError, IndexError):
            day_label = d
        daily_breakdown.append({
            'day': day_label,
            'date': d,
            'revenue': daily_rev.get(d, 0),
            'expense': daily_exp.get(d, 0),
        })

    month_revenue_prev = conn.execute("""
        SELECT COALESCE(SUM(price), 0) as total FROM appointments
        WHERE strftime('%Y-%m', appointment_date) = strftime('%Y-%m', 'now', 'localtime', '-1 month')
        AND status != 'cancelled'
    """).fetchone()['total']

    current_month_name = __import__('datetime').datetime.now().strftime('%B').capitalize()
    month_names = {
        'January': 'Janeiro', 'February': 'Fevereiro', 'March': 'Março',
        'April': 'Abril', 'May': 'Maio', 'June': 'Junho',
        'July': 'Julho', 'August': 'Agosto', 'September': 'Setembro',
        'October': 'Outubro', 'November': 'Novembro', 'December': 'Dezembro'
    }
    month_label = month_names.get(current_month_name, current_month_name)
    current_year = __import__('datetime').datetime.now().year

    return jsonify({
        'today_revenue': today_revenue,
        'today_count': today_count,
        'today_pending': today_pending,
        'active_clients': active_clients,
        'avg_ticket': round(avg_ticket, 2),
        'month_revenue': month_revenue,
        'month_expenses': month_expenses,
        'month_label': month_label,
        'month_year': current_year,
        'month_clients': month_clients_count,
        'weekly_revenue': weekly_revenue,
        'service_breakdown': service_breakdown,
        'service_revenue_breakdown': service_revenue_breakdown,
        'meta_mensal': meta_mensal,
        'meta_pct': meta_pct,
        'pix_pending': pix_pending,
        'total_revenue_all': total_revenue_all,
        'top_clients': [dict(c) for c in top_clients],
        'today_appointments': [dict(a) for a in today_appointments],
        'daily_breakdown': daily_breakdown,
        'recent_transactions': [dict(t) for t in recent_transactions],
        'expenses_by_category': expenses_by_category,
        'month_revenue_prev': month_revenue_prev,
    })


@app.errorhandler(404)
def not_found(e):
    return jsonify({'error': 'Rota não encontrada'}), 404


@app.errorhandler(500)
def server_error(e):
    return jsonify({'error': 'Erro interno do servidor'}), 500


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3001, debug=False)
