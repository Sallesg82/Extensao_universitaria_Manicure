import os
import json
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
TABLE_USERS = 'users'
TABLE_NOTIFICATIONS = 'notifications'
TABLE_INTEGRATIONS = 'integrations'
TABLE_BUSINESS_HOURS = 'business_hours'


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
    c['appointments'] = [
        {**row, 'appointment_time': row['appointment_time'][:5] if row.get('appointment_time') and len(row['appointment_time']) >= 5 else (row.get('appointment_time') or '')}
        for row in a.data
    ]
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
    all_appts = supabase.table(TABLE_APPOINTMENTS).select('price').neq('status', 'cancelled').execute()
    total_revenue_all = sum(a['price'] for a in all_appts.data)
    avg_ticket = round(total_revenue_all / len(all_appts.data), 2) if all_appts.data else 0

    # Active clients
    active = supabase.table(TABLE_CLIENTS).select('id', count='exact').execute()
    active_clients = active.count or 0

    # Meta
    meta_result = supabase.table(TABLE_SETTINGS).select('value').eq('key', 'meta_mensal').limit(1).execute()
    meta_mensal = 7000
    meta_pct = 0
    if meta_result.data:
        meta_mensal = float(meta_result.data[0]['value'])
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
        a['appointment_time'] = a['appointment_time'][:5] if a.get('appointment_time') and len(a['appointment_time']) >= 5 else (a.get('appointment_time') or '')
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


def _table_exists(name):
    try:
        supabase.table(name).select('id').limit(1).execute()
        return True
    except APIError:
        return False


def _ensure_users_table():
    if _table_exists(TABLE_USERS):
        return True
    import warnings
    warnings.warn(
        "Tabela 'users' não encontrada no Supabase.\n"
        "Execute o SQL abaixo no SQL Editor do seu projeto Supabase:\n\n"
        "CREATE TABLE IF NOT EXISTS users (\n"
        "    id SERIAL PRIMARY KEY,\n"
        "    name TEXT NOT NULL,\n"
        "    email TEXT NOT NULL UNIQUE,\n"
        "    phone TEXT DEFAULT '',\n"
        "    password_hash TEXT NOT NULL,\n"
        "    role TEXT NOT NULL DEFAULT 'admin',\n"
        "    created_at TIMESTAMPTZ DEFAULT NOW()\n"
        ");\n"
    )
    return False


_USERS_TABLE_OK = _ensure_users_table()


def all_users():
    if not _USERS_TABLE_OK:
        return []
    try:
        r = supabase.table(TABLE_USERS).select('id,name,email,phone,role,created_at').order('name').execute()
        return r.data
    except APIError:
        return []


def get_user(user_id):
    if not _USERS_TABLE_OK:
        return None
    try:
        r = supabase.table(TABLE_USERS).select('*').eq('id', user_id).limit(1).execute()
        return r.data[0] if r.data else None
    except APIError:
        return None


def get_user_by_email(email):
    if not _USERS_TABLE_OK:
        return None
    try:
        r = supabase.table(TABLE_USERS).select('*').eq('email', email).limit(1).execute()
        return r.data[0] if r.data else None
    except APIError:
        return None


def create_user(name, email, password_hash, phone='', role='admin'):
    if not _USERS_TABLE_OK:
        return None
    try:
        r = supabase.table(TABLE_USERS).insert({
            'name': name,
            'email': email,
            'phone': phone,
            'password_hash': password_hash,
            'role': role,
        }).execute()
        return r.data[0] if r.data else None
    except APIError:
        return None


def update_user(user_id, data):
    if not _USERS_TABLE_OK:
        return None
    try:
        supabase.table(TABLE_USERS).update(data).eq('id', user_id).execute()
        r = supabase.table(TABLE_USERS).select('id,name,email,phone,role,created_at').eq('id', user_id).single().execute()
        return r.data
    except APIError:
        return None


def delete_user(user_id):
    if not _USERS_TABLE_OK:
        return
    try:
        supabase.table(TABLE_USERS).delete().eq('id', user_id).execute()
    except APIError:
        pass


# ── Notifications ─────────────────────────────────────────────────────────────


def create_notification(notif_type, title, message, related_id=None, related_type=''):
    try:
        r = supabase.table(TABLE_NOTIFICATIONS).insert({
            'type': notif_type,
            'title': title,
            'message': message,
            'related_id': related_id,
            'related_type': related_type,
        }).execute()
        return r.data[0] if r.data else None
    except APIError:
        return None


def get_notifications(limit=20):
    try:
        r = supabase.table(TABLE_NOTIFICATIONS).select('*').order('created_at', desc=True).limit(limit).execute()
        return r.data
    except APIError:
        return []


def unread_notifications_count():
    try:
        r = supabase.table(TABLE_NOTIFICATIONS).select('id', count='exact').eq('read', False).execute()
        return r.count or 0
    except APIError:
        return 0


def mark_notification_read(notif_id):
    try:
        supabase.table(TABLE_NOTIFICATIONS).update({'read': True}).eq('id', notif_id).execute()
    except APIError:
        pass


def mark_all_notifications_read():
    try:
        supabase.table(TABLE_NOTIFICATIONS).update({'read': True}).eq('read', False).execute()
    except APIError:
        pass


# ── Integrations ──────────────────────────────────────────────────────────────


def list_integrations():
    try:
        r = supabase.table(TABLE_INTEGRATIONS).select('*').order('created_at').execute()
        return r.data
    except APIError:
        return []


def get_integration(integ_id):
    try:
        r = supabase.table(TABLE_INTEGRATIONS).select('*').eq('id', integ_id).limit(1).execute()
        return r.data[0] if r.data else None
    except APIError:
        return None


def create_integration(name, integ_type, config=None, enabled=True):
    try:
        r = supabase.table(TABLE_INTEGRATIONS).insert({
            'name': name,
            'type': integ_type,
            'config': config or {},
            'enabled': enabled,
        }).execute()
        return r.data[0] if r.data else None
    except APIError:
        return None


def update_integration(integ_id, data):
    try:
        supabase.table(TABLE_INTEGRATIONS).update(data).eq('id', integ_id).execute()
        r = supabase.table(TABLE_INTEGRATIONS).select('*').eq('id', integ_id).limit(1).execute()
        return r.data[0] if r.data else None
    except APIError:
        return None


def delete_integration(integ_id):
    try:
        supabase.table(TABLE_INTEGRATIONS).delete().eq('id', integ_id).execute()
    except APIError:
        pass


# ── Business Hours ──────────────────────────────────────────────────────────

DAYS_PT = ['segunda', 'terca', 'quarta', 'quinta', 'sexta', 'sabado', 'domingo']

DEFAULT_HOURS = {
    'segunda': {'open': '08:00', 'close': '18:00', 'closed': False},
    'terca':   {'open': '08:00', 'close': '18:00', 'closed': False},
    'quarta':  {'open': '08:00', 'close': '18:00', 'closed': False},
    'quinta':  {'open': '08:00', 'close': '18:00', 'closed': False},
    'sexta':   {'open': '08:00', 'close': '18:00', 'closed': False},
    'sabado':  {'open': '08:00', 'close': '13:00', 'closed': False},
    'domingo': {'open': '', 'close': '', 'closed': True},
}

_BH_ALERTADO = False

_BH_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS business_hours (
    id          SERIAL PRIMARY KEY,
    day         TEXT NOT NULL UNIQUE,
    open        TEXT NOT NULL DEFAULT '08:00',
    close       TEXT NOT NULL DEFAULT '18:00',
    closed      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TRIGGER IF NOT EXISTS trg_business_hours_updated_at
    BEFORE UPDATE ON business_hours
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

INSERT INTO business_hours (day, open, close, closed) VALUES
    ('segunda', '08:00', '18:00', FALSE),
    ('terca',   '08:00', '18:00', FALSE),
    ('quarta',  '08:00', '18:00', FALSE),
    ('quinta',  '08:00', '18:00', FALSE),
    ('sexta',   '08:00', '18:00', FALSE),
    ('sabado',  '08:00', '13:00', FALSE),
    ('domingo', '',      '',      TRUE)
ON CONFLICT (day) DO NOTHING;
"""


_MIGRATION_SQL = _BH_TABLE_SQL + """

-- Adicionar coluna buffer se não existir (margem extra entre agendamentos)
ALTER TABLE services ADD COLUMN IF NOT EXISTS buffer INTEGER NOT NULL DEFAULT 15;
"""


def _criar_tabela_business_hours():
    global _BH_ALERTADO
    if _BH_ALERTADO:
        return
    _BH_ALERTADO = True
    sql_path = os.path.join(os.path.dirname(__file__), 'criar_business_hours.sql')
    with open(sql_path, 'w') as f:
        f.write(_MIGRATION_SQL)
    print(f"[DB] Tabela 'business_hours' não encontrada no Supabase.")
    print(f"[DB] SQL para criar foi salvo em: {sql_path}")
    print(f"[DB] Execute esse SQL no SQL Editor do Supabase e reinicie o servidor.")


def _migrate_business_hours():
    try:
        r = supabase.table(TABLE_BUSINESS_HOURS).select('id').limit(1).execute()
        if r.data:
            return
    except APIError:
        _criar_tabela_business_hours()
        return
    try:
        s = get_settings()
        raw = s.get('business_hours', '')
        if raw:
            data = json.loads(raw)
            rows = [{'day': k, 'open': v.get('open', ''), 'close': v.get('close', ''), 'closed': v.get('closed', False)} for k, v in data.items()]
            supabase.table(TABLE_BUSINESS_HOURS).upsert(rows, on_conflict='day').execute()
            supabase.table(TABLE_SETTINGS).delete().eq('key', 'business_hours').execute()
    except Exception:
        pass


def load_business_hours():
    try:
        r = supabase.table(TABLE_BUSINESS_HOURS).select('day,open,close,closed').execute()
        if r.data:
            return {row['day']: {'open': row['open'], 'close': row['close'], 'closed': row['closed']} for row in r.data}
    except APIError:
        _criar_tabela_business_hours()
    return dict(DEFAULT_HOURS)


def save_business_hours(data):
    for day_key, info in data.items():
        try:
            supabase.table(TABLE_BUSINESS_HOURS).upsert({
                'day': day_key,
                'open': info.get('open', ''),
                'close': info.get('close', ''),
                'closed': info.get('closed', False),
            }, on_conflict='day').execute()
        except APIError:
            _criar_tabela_business_hours()
            raise RuntimeError(
                f"Tabela 'business_hours' não existe no Supabase. "
                f"Execute o SQL gerado em 'db/criar_business_hours.sql' no SQL Editor do Supabase."
            )


def validate_appointment_hours(appointment_date, appointment_time, duration=60, buffer=0):
    """Returns None if valid, or an error message string if the appointment falls outside business hours."""
    try:
        dt = datetime.strptime(appointment_date, '%Y-%m-%d')
    except (ValueError, TypeError):
        return 'Data inválida'

    try:
        t_parts = appointment_time.split(':')
        appt_min = int(t_parts[0]) * 60 + int(t_parts[1])
    except (ValueError, IndexError, AttributeError):
        return 'Horário inválido'

    dow = dt.weekday()
    day_key = DAYS_PT[dow]

    hours = load_business_hours()
    day_hours = hours.get(day_key, {})

    if day_hours.get('closed', False):
        return 'Fechado neste dia'

    open_str = day_hours.get('open', '08:00')
    close_str = day_hours.get('close', '18:00')

    try:
        open_min = int(open_str.split(':')[0]) * 60 + int(open_str.split(':')[1])
        close_min = int(close_str.split(':')[0]) * 60 + int(close_str.split(':')[1])
    except (ValueError, IndexError):
        return 'Horário de funcionamento inválido'

    if appt_min < open_min:
        return f'O horário de funcionamento neste dia é {open_str} às {close_str}. O agendamento deve começar após {open_str}.'

    total = appt_min + duration + buffer
    if total > close_min:
        return f'O horário de funcionamento neste dia é {open_str} às {close_str}. O serviço termina após o fechamento.'

    return None
