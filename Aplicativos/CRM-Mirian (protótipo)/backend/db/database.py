import os
from datetime import datetime
from supabase import create_client
from postgrest import APIError

SUPABASE_URL = os.environ.get('SUPABASE_URL', 'https://omtqedkinvyslsucryze.supabase.co')
SUPABASE_KEY = os.environ.get('SUPABASE_KEY',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9tdHFlZGtpbnZ5c2xzdWNyeXplIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODg3MjEwNywiZXhwIjoyMDk0NDQ4MTA3fQ.9-oTfqWZQKIil_9N_zddYm6-VvA9rOLDyfPZ0HpTAis'
)

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

TABLE_CLIENTS = 'clients'
TABLE_APPOINTMENTS = 'appointments'
TABLE_SERVICES = 'services'
TABLE_TRANSACTIONS = 'transactions'
TABLE_SETTINGS = 'settings'


def get_db():
    return supabase


def all_clients():
    r = supabase.table(TABLE_CLIENTS).select('*').order('name').execute()
    rows = r.data
    for c in rows:
        a = supabase.table(TABLE_APPOINTMENTS).select(
            'id', count='exact'
        ).eq('client_id', c['id']).execute()
        c['visits'] = a.count or 0
        fin = supabase.table(TABLE_APPOINTMENTS).select(
            'price'
        ).eq('client_id', c['id']).neq('status', 'cancelled').execute()
        c['total_spent'] = sum(row.get('price', 0) or 0 for row in fin.data)
        last = supabase.table(TABLE_APPOINTMENTS).select(
            'appointment_date'
        ).eq('client_id', c['id']).order('appointment_date', desc=True).limit(1).execute()
        c['last_visit'] = last.data[0]['appointment_date'] if last.data else None
    return rows


def get_client(client_id):
    r = supabase.table(TABLE_CLIENTS).select('*').eq('id', client_id).single().execute()
    c = r.data
    a = supabase.table(TABLE_APPOINTMENTS).select('*').eq('client_id', client_id).order('appointment_date', desc=True).order('appointment_time', desc=True).execute()
    visit_count = supabase.table(TABLE_APPOINTMENTS).select('id', count='exact').eq('client_id', client_id).execute()
    fin = supabase.table(TABLE_APPOINTMENTS).select('price').eq('client_id', client_id).neq('status', 'cancelled').execute()
    last = supabase.table(TABLE_APPOINTMENTS).select('appointment_date').eq('client_id', client_id).order('appointment_date', desc=True).limit(1).execute()
    c['visits'] = visit_count.count or 0
    c['total_spent'] = sum(row.get('price', 0) or 0 for row in fin.data)
    c['last_visit'] = last.data[0]['appointment_date'] if last.data else None
    c['appointments'] = a.data
    return c


def create_client(name, phone, email='', avatar_initials='', avatar_bg='#daeaf8',
                  avatar_color='#1a5fab', notes='', status='regular'):
    ini = avatar_initials or ''.join(w[0] for w in name.split())[:2].upper()
    r = supabase.table(TABLE_CLIENTS).insert({
        'name': name,
        'phone': phone,
        'email': email,
        'avatar_initials': ini,
        'avatar_bg': avatar_bg,
        'avatar_color': avatar_color,
        'notes': notes,
        'status': status,
    }).execute()
    return r.data[0]


def update_client(client_id, data):
    supabase.table(TABLE_CLIENTS).update(data).eq('id', client_id).execute()
    return get_client(client_id)


def delete_client(client_id):
    supabase.table(TABLE_APPOINTMENTS).delete().eq('client_id', client_id).execute()
    supabase.table(TABLE_CLIENTS).delete().eq('id', client_id).execute()


def get_settings():
    r = supabase.table(TABLE_SETTINGS).select('*').execute()
    return {row['key']: row['value'] for row in r.data}


def update_setting(key, value):
    supabase.table(TABLE_SETTINGS).upsert({'key': key, 'value': str(value)}).execute()


def get_stats():
    now = datetime.now()
    today = now.strftime('%Y-%m-%d')
    month_start = now.strftime('%Y-%m-01')
    prev_month = now.replace(day=1)
    if prev_month.month == 1:
        prev_month = prev_month.replace(year=prev_month.year - 1, month=12)
    else:
        prev_month = prev_month.replace(month=prev_month.month - 1)
    prev_month_start = prev_month.strftime('%Y-%m-01')
    prev_month_end = now.strftime('%Y-%m-01')

    # Today
    today_appts = supabase.table(TABLE_APPOINTMENTS).select('*').eq('appointment_date', today).order('appointment_time').execute()
    today_count = len(today_appts.data)
    today_revenue = sum(a['price'] for a in today_appts.data if a['status'] != 'cancelled')
    today_pending = sum(1 for a in today_appts.data if a['status'] == 'pending')

    # Month
    month_appts = supabase.table(TABLE_APPOINTMENTS).select('*').gte('appointment_date', month_start).lte('appointment_date', today).execute()
    month_revenue = sum(a['price'] for a in month_appts.data if a['status'] != 'cancelled')
    month_appointments_count = len(month_appts.data)

    month_trans = supabase.table(TABLE_TRANSACTIONS).select('*').gte('date', month_start).lte('date', today).execute()
    month_expenses = sum(t['amount'] for t in month_trans.data if t['type'] == 'expense')

    month_clients = supabase.table(TABLE_APPOINTMENTS).select('client_id').gte('appointment_date', month_start).execute()
    month_clients_count = len(set(a['client_id'] for a in month_clients.data))

    # All time
    total_revenue = supabase.table(TABLE_APPOINTMENTS).select('price').neq('status', 'cancelled').execute()
    total_revenue_all = sum(a['price'] for a in total_revenue.data)

    all_appts = supabase.table(TABLE_APPOINTMENTS).select('price').neq('status', 'cancelled').execute()
    avg_ticket = round(sum(a['price'] for a in all_appts.data) / len(all_appts.data), 2) if all_appts.data else 0

    # Active clients
    active = supabase.table(TABLE_CLIENTS).select('id', count='exact').execute()
    active_clients = active.count or 0

    # Meta
    meta_row = supabase.table(TABLE_SETTINGS).select('value').eq('key', 'meta_mensal').single().execute()
    meta_mensal = float(meta_row.data['value']) if meta_row.data else 7000
    meta_pct = round((month_revenue / meta_mensal) * 100, 1) if meta_mensal > 0 else 0

    # Top clients
    all_clients_data = supabase.table(TABLE_CLIENTS).select('id,name,avatar_initials,avatar_bg,avatar_color').execute()
    top_clients = []
    for cl in all_clients_data.data:
        ca = supabase.table(TABLE_APPOINTMENTS).select('price', 'appointment_date', count='exact').eq('client_id', cl['id']).neq('status', 'cancelled').execute()
        visits = ca.count or 0
        total_spent = sum(a['price'] for a in ca.data)
        last_visit = max((a['appointment_date'] for a in ca.data if a.get('appointment_date')), default=None)
        top_clients.append({**cl, 'visits': visits, 'total_spent': total_spent, 'last_visit': last_visit})
    top_clients.sort(key=lambda x: -x['total_spent'])
    top_clients = top_clients[:5]

    # Today appointments with client names
    today_full = []
    for a in today_appts.data:
        cl = supabase.table(TABLE_CLIENTS).select('name,phone').eq('id', a['client_id']).single().execute()
        today_full.append({**a, 'client_name': cl.data['name'], 'client_phone': cl.data.get('phone', '')})

    # Service breakdown
    svc_counts = {}
    svc_revenue = {}
    for a in month_appts.data:
        if a['status'] == 'cancelled':
            continue
        svc_counts[a['service']] = svc_counts.get(a['service'], 0) + 1
        svc_revenue[a['service']] = svc_revenue.get(a['service'], 0) + a['price']
    total_svc = sum(svc_counts.values()) or 1
    total_svc_rev = sum(svc_revenue.values()) or 1
    service_breakdown = sorted([
        {'name': k, 'count': v, 'pct': round(v / total_svc * 100, 1)}
        for k, v in svc_counts.items()
    ], key=lambda x: -x['count'])[:5]
    service_revenue_breakdown = sorted([
        {'name': k, 'revenue': v, 'pct': round(v / total_svc_rev * 100, 1)}
        for k, v in svc_revenue.items()
    ], key=lambda x: -x['revenue'])[:5]

    # Weekly revenue
    weekly_rev = {}
    for a in month_appts.data:
        if a['status'] == 'cancelled':
            continue
        try:
            d = datetime.strptime(a['appointment_date'], '%Y-%m-%d')
            week = (d.day - 1) // 7
            weekly_rev[week] = weekly_rev.get(week, 0) + a['price']
        except (ValueError, TypeError):
            pass
    weekly_revenue = [weekly_rev.get(i, 0) for i in range(max(weekly_rev.keys()) + 1)] if weekly_rev else []

    # Daily breakdown
    day_names_pt = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab']
    daily_rev = {}
    daily_exp = {}
    for a in month_appts.data:
        if a['status'] != 'cancelled':
            daily_rev[a['appointment_date']] = daily_rev.get(a['appointment_date'], 0) + a['price']
    for t in month_trans.data:
        if t['type'] == 'expense':
            daily_exp[t['date']] = daily_exp.get(t['date'], 0) + t['amount']
        else:
            daily_rev[t['date']] = daily_rev.get(t['date'], 0) + t['amount']
    all_days = sorted(set(list(daily_rev.keys()) + list(daily_exp.keys())))
    daily_breakdown = []
    for d in all_days:
        try:
            dt = datetime.strptime(d, '%Y-%m-%d')
            day_label = day_names_pt[dt.weekday()]
        except (ValueError, IndexError):
            day_label = d
        daily_breakdown.append({
            'day': day_label,
            'date': d,
            'revenue': daily_rev.get(d, 0),
            'expense': daily_exp.get(d, 0),
        })

    # Pix pending
    pix = supabase.table(TABLE_TRANSACTIONS).select('id', count='exact').eq('type', 'income').eq('payment_method', 'Pix').gte('date', month_start).execute()
    pix_pending = pix.count or 0

    # Recent transactions
    recent_tx = supabase.table(TABLE_TRANSACTIONS).select('*').gte('date', month_start).order('date', desc=True).order('id', desc=True).limit(10).execute()
    recent_transactions = []
    for t in recent_tx.data:
        if t.get('appointment_id'):
            a = supabase.table(TABLE_APPOINTMENTS).select('client_id').eq('id', t['appointment_id']).single().execute()
            if a.data:
                cl = supabase.table(TABLE_CLIENTS).select('name').eq('id', a.data['client_id']).single().execute()
                t['client_name'] = cl.data['name'] if cl.data else None
        recent_transactions.append(t)

    # Expenses by category
    exp_cat = supabase.table(TABLE_TRANSACTIONS).select('category, amount').eq('type', 'expense').gte('date', month_start).execute()
    cat_totals = {}
    for t in exp_cat.data:
        cat_totals[t['category'] or 'Outros'] = cat_totals.get(t['category'] or 'Outros', 0) + t['amount']
    total_exp = sum(cat_totals.values()) or 1
    expenses_by_category = [
        {'category': cat, 'amount': val, 'pct': round(val / total_exp * 100, 1)}
        for cat, val in sorted(cat_totals.items(), key=lambda x: -x[1])
    ]

    # Previous month revenue
    prev_appts = supabase.table(TABLE_APPOINTMENTS).select('price').gte('appointment_date', prev_month_start).lt('appointment_date', prev_month_end).neq('status', 'cancelled').execute()
    month_revenue_prev = sum(a['price'] for a in prev_appts.data)

    month_label_pt = {
        1: 'Janeiro', 2: 'Fevereiro', 3: 'Marco', 4: 'Abril',
        5: 'Maio', 6: 'Junho', 7: 'Julho', 8: 'Agosto',
        9: 'Setembro', 10: 'Outubro', 11: 'Novembro', 12: 'Dezembro'
    }

    return {
        'today_revenue': today_revenue,
        'today_count': today_count,
        'today_pending': today_pending,
        'active_clients': active_clients,
        'avg_ticket': avg_ticket,
        'month_revenue': month_revenue,
        'month_expenses': month_expenses,
        'month_label': month_label_pt.get(now.month, ''),
        'month_year': now.year,
        'month_clients': month_clients_count,
        'weekly_revenue': weekly_revenue,
        'service_breakdown': service_breakdown,
        'service_revenue_breakdown': service_revenue_breakdown,
        'meta_mensal': meta_mensal,
        'meta_pct': meta_pct,
        'pix_pending': pix_pending,
        'total_revenue_all': total_revenue_all,
        'top_clients': top_clients,
        'today_appointments': today_full,
        'daily_breakdown': daily_breakdown,
        'recent_transactions': recent_transactions,
        'expenses_by_category': expenses_by_category,
        'month_revenue_prev': month_revenue_prev,
    }
