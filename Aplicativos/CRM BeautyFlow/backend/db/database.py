import os
import re
import json
from datetime import datetime, timedelta, date, time
import calendar
from decimal import Decimal
from psycopg_pool import ConnectionPool
from psycopg.rows import dict_row

raw_url = os.environ.get('DATABASE_URL',
                          'postgresql://postgres:beautyflow_pass@localhost:5432/beautyflow')

# Se não estiver dentro do Docker e a URL apontar para o host 'postgres', usa 'localhost'
if '@postgres:' in raw_url:
    try:
        import socket
        socket.gethostbyname('postgres')
    except Exception:
        raw_url = raw_url.replace('@postgres:', '@localhost:')

DATABASE_URL = raw_url

_pool = None


def _get_pool():
    global _pool
    if _pool is None or getattr(_pool, 'closed', False):
        _pool = ConnectionPool(DATABASE_URL, min_size=1, max_size=10,
                               open=False, kwargs={'row_factory': dict_row})
        _pool.open(wait=True, timeout=30)
    return _pool


class DataNotFound(Exception):
    pass


def _conv(v):
    if isinstance(v, datetime):
        return v.strftime('%Y-%m-%dT%H:%M:%S')
    if isinstance(v, date):
        return v.strftime('%Y-%m-%d')
    if isinstance(v, time):
        return v.strftime('%H:%M:%S')
    if isinstance(v, Decimal):
        return float(v)
    return v


def _rows(rows):
    return [{k: _conv(v) for k, v in r.items()} for r in rows]


def _run(sql, params=()):
    with _get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            if cur.description:
                return cur.fetchall()
            return []


TABLE_CLIENTS = 'clients'
TABLE_APPOINTMENTS = 'appointments'
TABLE_SERVICES = 'services'
TABLE_TRANSACTIONS = 'transactions'
TABLE_SETTINGS = 'settings'
TABLE_USERS = 'users'
TABLE_NOTIFICATIONS = 'notifications'
TABLE_INTEGRATIONS = 'integrations'
TABLE_BUSINESS_HOURS = 'business_hours'

# Receita financeira só conta após o atendimento ser concluído
REVENUE_APPOINTMENT_STATUS = 'done'

DEFAULT_CONFLICT_COLS = {
    TABLE_SETTINGS: 'key',
    TABLE_BUSINESS_HOURS: 'day',
    TABLE_USERS: 'email',
    TABLE_SERVICES: 'name',
}


def counts_as_revenue(status):
    return status == REVENUE_APPOINTMENT_STATUS


class Result:
    def __init__(self, data, count=None):
        self.data = data
        self.count = count


class TableBuilder:
    _JOIN_RE = re.compile(r'^(.+?)\s*,\s*(\w+)\s*\(\s*([^)]*)\)\s*$')

    def __init__(self, table):
        self.table = table
        self._op = 'select'
        self._cols = '*'
        self._count_exact = False
        self._filters = []
        self._orders = []
        self._limit_n = None
        self._single = False
        self._payload = None
        self._conflict = None

    # ── método chain ─────────────────────────────────────────────────────

    def select(self, *cols, count=None):
        self._op = 'select'
        self._cols = ','.join(cols) if cols else '*'
        if count == 'exact':
            self._count_exact = True
        return self

    def eq(self, col, val):
        self._filters.append(('=', col, val))
        return self

    def neq(self, col, val):
        self._filters.append(('<>', col, val))
        return self

    def gte(self, col, val):
        self._filters.append(('>=', col, val))
        return self

    def lte(self, col, val):
        self._filters.append(('<=', col, val))
        return self

    def order(self, col, desc=False):
        self._orders.append((col, 'DESC' if desc else 'ASC'))
        return self

    def limit(self, n):
        self._limit_n = n
        return self

    def single(self):
        self._single = True
        return self

    def insert(self, payload):
        self._op = 'insert'
        self._payload = payload
        return self

    def upsert(self, payload, on_conflict=None):
        self._op = 'upsert'
        self._payload = payload
        self._conflict = on_conflict
        return self

    def update(self, payload):
        self._op = 'update'
        self._payload = payload
        return self

    def delete(self):
        self._op = 'delete'
        return self

    # ── execução ─────────────────────────────────────────────────────────

    def _where_sql(self, qualify=False):
        if not self._filters:
            return '', []
        clauses = []
        params = []
        for op, col, val in self._filters:
            col_ref = f'"{self.table}"."{col}"' if qualify else f'"{col}"'
            clauses.append(f'{col_ref} {op} %s')
            params.append(val)
        return ' WHERE ' + ' AND '.join(clauses), params

    def _order_sql(self, qualify=False):
        if not self._orders:
            return ''
        parts = []
        for c, d in self._orders:
            col_ref = f'"{self.table}"."{c}"' if qualify else f'"{c}"'
            parts.append(f'{col_ref} {d}')
        return ' ORDER BY ' + ', '.join(parts)

    def execute(self):
        if self._op == 'select':
            return self._exec_select()
        if self._op == 'insert':
            return self._exec_insert()
        if self._op == 'upsert':
            return self._exec_upsert()
        if self._op == 'update':
            return self._exec_update()
        if self._op == 'delete':
            return self._exec_delete()
        raise RuntimeError('Operação não suportada')

    def _exec_select(self):
        main_cols = self._cols
        join_table = None
        join_cols = None
        m = self._JOIN_RE.match(self._cols)
        if m:
            main_cols, join_table, join_cols = m.group(1).strip(), m.group(2), [c.strip() for c in m.group(3).split(',') if c.strip()]

        where, params = self._where_sql(qualify=bool(join_table))

        if self._count_exact and not join_table:
            count_rows = _run(
                f'SELECT COUNT(*) AS total FROM "{self.table}"{where}',
                params
            )
            total = count_rows[0]['total'] if count_rows else 0
        else:
            total = None

        select_parts = ['"{0}".*'.format(self.table) if main_cols.strip() == '*' else main_cols]
        if join_table:
            alias = 'j'
            select_parts.append(', '.join(
                f'{alias}."{c}" AS "__j_{c}"' for c in join_cols
            ))
        if self._count_exact and join_table:
            select_parts.append('COUNT(*) OVER() AS "__bf_count"')

        sql = f'SELECT {", ".join(select_parts)} FROM "{self.table}"'
        if join_table:
            singular = join_table[:-1] if join_table.endswith('s') else join_table
            sql += f' LEFT JOIN "{join_table}" {alias} ON {alias}.id = "{self.table}"."{singular}_id"'
        sql += where + self._order_sql(qualify=bool(join_table))
        if self._limit_n:
            sql += f' LIMIT {int(self._limit_n)}'

        raw = _run(sql, params)
        data = []
        for r in raw:
            row = {k: _conv(v) for k, v in r.items()}
            if join_table:
                joined = {}
                for c in join_cols:
                    key = f'__j_{c}'
                    if key in row:
                        joined[c] = row.pop(key)
                row[join_table] = joined
            data.append(row)

        if self._count_exact and join_table and data:
            total = data[0].pop('__bf_count')

        if self._single:
            if not data:
                raise DataNotFound(f'Registro não encontrado em {self.table}')
            return Result(data[0])
        return Result(data, count=total)

    def _exec_insert(self):
        payload = dict(self._payload)
        cols = list(payload.keys())
        col_sql = ', '.join(f'"{c}"' for c in cols)
        placeholders = ', '.join(['%s'] * len(cols))
        sql = (f'INSERT INTO "{self.table}" ({col_sql}) VALUES ({placeholders}) '
               f'RETURNING *')
        raw = _run(sql, [payload[c] for c in cols])
        data = _rows(raw)
        if self._single:
            return Result(data[0] if data else {})
        return Result(data)

    def _exec_upsert(self):
        payload = self._payload
        if isinstance(payload, dict):
            payload = [payload]
        if not isinstance(payload, (list, tuple)) or not payload:
            return Result([])
        results = []
        for row in payload:
            data = dict(row)
            cols = list(data.keys())
            if not cols:
                continue
            col_sql = ', '.join(f'"{c}"' for c in cols)
            placeholders = ', '.join(['%s'] * len(cols))
            conflict_col = self._conflict or DEFAULT_CONFLICT_COLS.get(self.table)
            if not conflict_col and 'id' in cols:
                conflict_col = 'id'
            if conflict_col and conflict_col in cols:
                update_cols = ', '.join(
                    f'"{c}" = EXCLUDED."{c}"' for c in cols if c != conflict_col
                )
                if update_cols:
                    conflict_sql = f'ON CONFLICT ("{conflict_col}") DO UPDATE SET {update_cols}'
                else:
                    conflict_sql = f'ON CONFLICT ("{conflict_col}") DO NOTHING'
            else:
                conflict_sql = ''
            sql = (f'INSERT INTO "{self.table}" ({col_sql}) VALUES ({placeholders}) '
                   f'{conflict_sql} RETURNING *')
            raw = _run(sql, [data[c] for c in cols])
            results.extend(_rows(raw))
        return Result(results)

    def _exec_update(self):
        payload = dict(self._payload)
        cols = list(payload.keys())
        set_sql = ', '.join(f'"{c}" = %s' for c in cols)
        where, params = self._where_sql()
        sql = (f'UPDATE "{self.table}" SET {set_sql}{where} RETURNING *')
        raw = _run(sql, [payload[c] for c in cols] + params)
        data = _rows(raw)
        if self._single:
            if not data:
                raise DataNotFound(f'Registro não encontrado em {self.table}')
            return Result(data[0])
        return Result(data)

    def _exec_delete(self):
        where, params = self._where_sql()
        sql = f'DELETE FROM "{self.table}"{where} RETURNING *'
        raw = _run(sql, params)
        return Result(_rows(raw))


class PostgresClient:
    def table(self, name):
        return TableBuilder(name)


_db_client = PostgresClient()


def get_db():
    return _db_client


# ══════════════════════════════════════════════════════════════════════════
# Schema + seed
# ══════════════════════════════════════════════════════════════════════════

_SCHEMA_SQL = r"""
CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS clients (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    phone           TEXT NOT NULL,
    email           TEXT DEFAULT '',
    avatar_initials TEXT NOT NULL,
    avatar_bg       TEXT NOT NULL DEFAULT '#daeaf8',
    avatar_color    TEXT NOT NULL DEFAULT '#1a5fab',
    cpf             TEXT DEFAULT '',
    notes           TEXT DEFAULT '',
    status          TEXT DEFAULT 'regular',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_clients_name ON clients (name);
CREATE INDEX IF NOT EXISTS idx_clients_phone ON clients (phone);
CREATE INDEX IF NOT EXISTS idx_clients_status ON clients (status);
DROP TRIGGER IF EXISTS trg_clients_updated_at ON clients;
CREATE TRIGGER trg_clients_updated_at
    BEFORE UPDATE ON clients
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TABLE IF NOT EXISTS appointments (
    id                SERIAL PRIMARY KEY,
    client_id         INTEGER REFERENCES clients(id) ON DELETE SET NULL,
    service           TEXT NOT NULL,
    appointment_date  DATE NOT NULL,
    appointment_time  TIME NOT NULL,
    status            TEXT NOT NULL DEFAULT 'pending',
    payment_status    TEXT NOT NULL DEFAULT 'unpaid' CHECK(payment_status IN ('paid', 'unpaid')),
    price             REAL NOT NULL DEFAULT 0,
    duration          INTEGER DEFAULT 60,
    notes             TEXT DEFAULT '',
    google_event_id   TEXT DEFAULT '',
    google_html_link  TEXT DEFAULT '',
    created_at        TIMESTAMPTZ DEFAULT NOW(),
    updated_at        TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_appointments_client ON appointments (client_id);
CREATE INDEX IF NOT EXISTS idx_appointments_date ON appointments (appointment_date);
CREATE INDEX IF NOT EXISTS idx_appointments_status ON appointments (status);
CREATE INDEX IF NOT EXISTS idx_appointments_payment_status ON appointments (payment_status);
CREATE INDEX IF NOT EXISTS idx_appointments_client_date ON appointments (client_id, appointment_date);
DROP TRIGGER IF EXISTS trg_appointments_updated_at ON appointments;
CREATE TRIGGER trg_appointments_updated_at
    BEFORE UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TABLE IF NOT EXISTS services (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    duration    INTEGER NOT NULL DEFAULT 60,
    buffer      INTEGER NOT NULL DEFAULT 15,
    price       REAL NOT NULL DEFAULT 0,
    color       TEXT DEFAULT '#4a90d9',
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_services_name ON services (name);

CREATE TABLE IF NOT EXISTS transactions (
    id                SERIAL PRIMARY KEY,
    type              TEXT NOT NULL CHECK(type IN ('income', 'expense')),
    description       TEXT NOT NULL,
    amount            REAL NOT NULL,
    category          TEXT DEFAULT '',
    payment_method    TEXT DEFAULT '',
    date              DATE NOT NULL,
    appointment_id    INTEGER REFERENCES appointments(id) ON DELETE SET NULL,
    client_id         INTEGER REFERENCES clients(id) ON DELETE SET NULL,
    client_name       TEXT DEFAULT '',
    service           TEXT DEFAULT '',
    created_at        TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions (date);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions (type);
CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions (category);
CREATE INDEX IF NOT EXISTS idx_transactions_appointment ON transactions (appointment_id);
CREATE INDEX IF NOT EXISTS idx_transactions_client ON transactions (client_id);
CREATE INDEX IF NOT EXISTS idx_transactions_service ON transactions (service);

CREATE TABLE IF NOT EXISTS settings (
    key     TEXT PRIMARY KEY,
    value   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS business_hours (
    id          SERIAL PRIMARY KEY,
    day         TEXT NOT NULL UNIQUE,
    open        TEXT NOT NULL DEFAULT '08:00',
    close       TEXT NOT NULL DEFAULT '18:00',
    closed      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);
DROP TRIGGER IF EXISTS trg_business_hours_updated_at ON business_hours;
CREATE TRIGGER trg_business_hours_updated_at
    BEFORE UPDATE ON business_hours
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TABLE IF NOT EXISTS notifications (
    id              SERIAL PRIMARY KEY,
    type            TEXT NOT NULL,
    title           TEXT NOT NULL,
    message         TEXT NOT NULL,
    related_id      INTEGER DEFAULT NULL,
    related_type    TEXT DEFAULT '',
    read            BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications (read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications (created_at DESC);

CREATE TABLE IF NOT EXISTS integrations (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    type        TEXT NOT NULL CHECK(type IN ('webhook', 'n8n', 'google_calendar')),
    config      JSONB DEFAULT '{}',
    enabled     BOOLEAN DEFAULT TRUE,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_integrations_type ON integrations (type);
CREATE INDEX IF NOT EXISTS idx_integrations_enabled ON integrations (enabled);
DROP TRIGGER IF EXISTS trg_integrations_updated_at ON integrations;
CREATE TRIGGER trg_integrations_updated_at
    BEFORE UPDATE ON integrations
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TABLE IF NOT EXISTS users (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    email           TEXT NOT NULL UNIQUE,
    phone           TEXT DEFAULT '',
    password_hash   TEXT NOT NULL,
    role            TEXT NOT NULL DEFAULT 'admin',
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);

CREATE OR REPLACE VIEW v_clients AS
SELECT c.*,
    COALESCE(a.visits, 0) AS visits,
    COALESCE(a.total_spent, 0) AS total_spent,
    a.last_visit
FROM clients c
LEFT JOIN LATERAL (
    SELECT
        COUNT(*) AS visits,
        COALESCE(SUM(CASE WHEN payment_status = 'paid' THEN price ELSE 0 END), 0) AS total_spent,
        MAX(appointment_date) AS last_visit
    FROM appointments
    WHERE client_id = c.id AND status != 'cancelled'
) a ON true;

CREATE OR REPLACE VIEW v_month_stats AS
SELECT
    COALESCE((
        SELECT SUM(amount) FROM transactions
        WHERE type = 'income'
          AND DATE_TRUNC('month', date) = DATE_TRUNC('month', CURRENT_DATE)
    ), 0) AS month_revenue,
    COUNT(*) AS month_appointments,
    COUNT(*) FILTER (WHERE a.status = 'pending') AS month_pending,
    COALESCE((
        SELECT SUM(amount) FROM transactions
        WHERE type = 'expense'
          AND DATE_TRUNC('month', date) = DATE_TRUNC('month', CURRENT_DATE)
    ), 0) AS month_expenses,
    COUNT(DISTINCT a.client_id) AS month_clients
FROM appointments a
WHERE DATE_TRUNC('month', a.appointment_date) = DATE_TRUNC('month', CURRENT_DATE);

CREATE OR REPLACE VIEW v_daily_stats AS
SELECT
    d.date,
    COALESCE(i.revenue, 0) AS revenue,
    COALESCE(e.expense, 0) AS expense
FROM (
    SELECT DISTINCT date FROM transactions
    WHERE DATE_TRUNC('month', date) = DATE_TRUNC('month', CURRENT_DATE)
) d
LEFT JOIN (
    SELECT date, SUM(amount) AS revenue
    FROM transactions
    WHERE type = 'income'
      AND DATE_TRUNC('month', date) = DATE_TRUNC('month', CURRENT_DATE)
    GROUP BY date
) i ON i.date = d.date
LEFT JOIN (
    SELECT date, SUM(amount) AS expense
    FROM transactions
    WHERE type = 'expense'
      AND DATE_TRUNC('month', date) = DATE_TRUNC('month', CURRENT_DATE)
    GROUP BY date
) e ON e.date = d.date
ORDER BY d.date;
"""


def init_schema():
    _run(_SCHEMA_SQL)


def ensure_admin_user():
    """Cria o usuário admin/admin padrão quando não existe nenhum usuário."""
    rows = _run('SELECT COUNT(*) AS total FROM users')
    if not rows or rows[0]['total'] > 0:
        return False
    from werkzeug.security import generate_password_hash
    pw_hash = generate_password_hash('admin')
    _run(
        "INSERT INTO users (name, email, phone, password_hash, role) "
        "VALUES (%s, %s, %s, %s, %s)",
        ('Administrador', 'admin', '', pw_hash, 'admin'),
    )
    print('[DB] Usuário padrão criado: admin / admin')
    return True


def ensure_default_data():
    """Garante que dados essenciais (horários, serviços e configurações) existam em instalações novas."""
    try:
        _run("""
            INSERT INTO business_hours (day, open, close, closed) VALUES
                ('segunda', '08:00', '18:00', false),
                ('terca',   '08:00', '18:00', false),
                ('quarta',  '08:00', '18:00', false),
                ('quinta',  '08:00', '18:00', false),
                ('sexta',   '08:00', '18:00', false),
                ('sabado',  '08:00', '13:00', false),
                ('domingo', '',      '',      true)
            ON CONFLICT (day) DO NOTHING;
        """)
        _run("""
            INSERT INTO services (name, duration, buffer, price, color) VALUES
                ('Manicure Tradicional', 45, 15, 45.0, '#E07A5F'),
                ('Pedicure Tradicional', 45, 15, 50.0, '#3D405B'),
                ('Combo Manicure + Pedicure', 80, 15, 85.0, '#81B29A'),
                ('Alongamento em Gel', 120, 15, 150.0, '#F2CC8F'),
                ('Spa dos Pés', 60, 15, 70.0, '#D4A373'),
                ('Esmaltação em Gel', 60, 15, 65.0, '#C084FC')
            ON CONFLICT (name) DO NOTHING;
        """)
        _run("""
            INSERT INTO settings (key, value) VALUES
                ('meta_mensal', '7000')
            ON CONFLICT (key) DO NOTHING;
        """)
    except Exception as e:
        print(f'[DB] Aviso ao garantir dados padrão: {e}')


try:
    init_schema()
    _USERS_TABLE_OK = True
    ensure_admin_user()
    ensure_default_data()
except Exception as e:
    print(f'[DB] Aviso: não foi possível inicializar o banco: {e}')
    _USERS_TABLE_OK = False


# ══════════════════════════════════════════════════════════════════════════
# Transações financeiras (receita por atendimento concluído)
# ══════════════════════════════════════════════════════════════════════════


def _tx_amount(tx):
    return float(tx.get('amount', 0) or 0)


def _income_transactions(date_from=None, date_to=None):
    sql = 'SELECT * FROM transactions WHERE type = %s'
    params = ['income']
    if date_from:
        sql += ' AND date >= %s'
        params.append(date_from)
    if date_to:
        sql += ' AND date <= %s'
        params.append(date_to)
    return _rows(_run(sql, params))


def _sum_income(transactions):
    return sum(_tx_amount(t) for t in transactions)


def _transaction_service_name(tx):
    service = (tx.get('service') or '').strip()
    if service:
        return service
    desc = (tx.get('description') or '').strip()
    if ' — ' in desc:
        return desc.split(' — ', 1)[0].strip()
    if ' - ' in desc:
        return desc.split(' - ', 1)[0].strip()
    return desc or 'Outros'


def _transaction_client_name(tx):
    name = (tx.get('client_name') or '').strip()
    if name:
        return name
    desc = (tx.get('description') or '').strip()
    if ' — ' in desc:
        return desc.split(' — ', 1)[1].strip()
    if ' - ' in desc:
        parts = desc.split(' - ', 1)
        if len(parts) > 1:
            return parts[1].strip()
    return desc


def _appointment_income_payload(appt, client_name):
    service = appt.get('service', '')
    return {
        'type': 'income',
        'amount': float(appt.get('price', 0) or 0),
        'date': appt['appointment_date'],
        'description': f"{service} — {client_name}",
        'category': 'Serviços',
        'payment_method': '',
        'appointment_id': appt['id'],
        'client_id': appt.get('client_id'),
        'client_name': client_name,
        'service': service,
    }


def _insert_transaction(payload):
    try:
        return get_db().table(TABLE_TRANSACTIONS).insert(payload).execute()
    except Exception:
        minimal = {
            k: payload[k]
            for k in ('type', 'amount', 'date', 'description', 'category', 'payment_method', 'appointment_id')
            if k in payload
        }
        return get_db().table(TABLE_TRANSACTIONS).insert(minimal).execute()


def _update_transaction(tx_id, payload):
    try:
        return get_db().table(TABLE_TRANSACTIONS).update(payload).eq('id', tx_id).execute()
    except Exception:
        minimal = {
            k: payload[k]
            for k in ('type', 'amount', 'date', 'description', 'category', 'payment_method', 'appointment_id')
            if k in payload
        }
        return get_db().table(TABLE_TRANSACTIONS).update(minimal).eq('id', tx_id).execute()


def sync_appointment_income(appt_id):
    """Lançamento financeiro imutável ao concluir; não some se cliente/agendamento for removido depois."""
    r = get_db().table(TABLE_APPOINTMENTS).select('*').eq('id', appt_id).limit(1).execute()
    if not r.data:
        return None

    appt = r.data[0]
    client_name = 'Cliente'
    try:
        cl = get_db().table(TABLE_CLIENTS).select('name').eq('id', appt['client_id']).limit(1).execute()
        if cl.data:
            client_name = cl.data[0].get('name') or client_name
    except Exception:
        pass

    existing = get_db().table(TABLE_TRANSACTIONS).select('id').eq('appointment_id', appt_id).eq('type', 'income').execute()

    if counts_as_revenue(appt.get('status')):
        payload = _appointment_income_payload(appt, client_name)
        if existing.data:
            _update_transaction(existing.data[0]['id'], payload)
            return existing.data[0]['id']
        result = _insert_transaction(payload)
        return result.data[0]['id'] if result.data else None

    for tx in existing.data:
        get_db().table(TABLE_TRANSACTIONS).delete().eq('id', tx['id']).execute()
    return None


def backfill_appointment_income_transactions():
    """Cria lançamentos para atendimentos concluídos que ainda não têm receita financeira."""
    done = get_db().table(TABLE_APPOINTMENTS).select('id').eq('status', REVENUE_APPOINTMENT_STATUS).execute()
    for row in done.data:
        appt_id = row['id']
        linked = get_db().table(TABLE_TRANSACTIONS).select('id').eq('appointment_id', appt_id).eq('type', 'income').limit(1).execute()
        if not linked.data:
            sync_appointment_income(appt_id)


def _counts_as_revenue(appt):
    """Receita contabilizada apenas quando o pagamento está confirmado."""
    return appt.get('payment_status') == 'paid'


# ══════════════════════════════════════════════════════════════════════════
# Clientes
# ══════════════════════════════════════════════════════════════════════════


def all_clients():
    sql = (
        'SELECT c.*, COUNT(a.id) AS visits, '
        'COALESCE(SUM(a.price) FILTER (WHERE a.status = %s), 0) AS total_spent, '
        'MAX(a.appointment_date) AS last_visit '
        'FROM clients c LEFT JOIN appointments a ON a.client_id = c.id '
        'GROUP BY c.id ORDER BY c.name'
    )
    return _rows(_run(sql, [REVENUE_APPOINTMENT_STATUS]))


def get_client(client_id):
    r = get_db().table(TABLE_CLIENTS).select('*').eq('id', client_id).single().execute()
    c = r.data
    a = get_db().table(TABLE_APPOINTMENTS).select('*').eq('client_id', client_id).order('appointment_date', desc=True).order('appointment_time', desc=True).execute()
    appts = a.data or []
    c['visits'] = len(appts)
    c['total_spent'] = sum(float(row.get('price', 0) or 0) for row in appts if counts_as_revenue(row.get('status')))
    c['last_visit'] = appts[0]['appointment_date'] if appts else None
    c['appointments'] = [
        {**row, 'appointment_time': row['appointment_time'][:5] if row.get('appointment_time') and len(row['appointment_time']) >= 5 else (row.get('appointment_time') or '')}
        for row in appts
    ]
    svc_usage = {}
    for row in appts:
        if counts_as_revenue(row.get('status')):
            svc = row.get('service') or 'Outros'
            svc_usage[svc] = svc_usage.get(svc, 0) + 1
    c['service_usage'] = sorted(
        [{'service': name, 'count': count} for name, count in svc_usage.items()],
        key=lambda x: -x['count']
    )
    return c


def create_client(name, phone, email='', avatar_initials='', avatar_bg='#daeaf8',
                  avatar_color='#1a5fab', notes='', status='regular', cpf=''):
    ini = avatar_initials or ''.join(w[0] for w in name.split())[:2].upper()
    payload = {
        'name': name,
        'phone': phone,
        'email': email,
        'avatar_initials': ini,
        'avatar_bg': avatar_bg,
        'avatar_color': avatar_color,
        'notes': notes,
        'status': status,
    }
    if cpf:
        payload['cpf'] = cpf
    try:
        r = get_db().table(TABLE_CLIENTS).insert(payload).execute()
    except Exception:
        payload.pop('cpf', None)
        r = get_db().table(TABLE_CLIENTS).insert(payload).execute()
    return r.data[0]


def update_client(client_id, data):
    get_db().table(TABLE_CLIENTS).update(data).eq('id', client_id).execute()
    return get_client(client_id)


def delete_client(client_id):
    get_db().table(TABLE_CLIENTS).delete().eq('id', client_id).execute()


# ══════════════════════════════════════════════════════════════════════════
# Settings
# ══════════════════════════════════════════════════════════════════════════


def get_settings():
    r = get_db().table(TABLE_SETTINGS).select('*').execute()
    return {row['key']: row['value'] for row in r.data}


def update_setting(key, value):
    sql = 'INSERT INTO "settings" ("key", "value") VALUES (%s, %s) ON CONFLICT ("key") DO UPDATE SET "value" = EXCLUDED."value"'
    _run(sql, (str(key), str(value)))


# ══════════════════════════════════════════════════════════════════════════
# Stats
# ══════════════════════════════════════════════════════════════════════════


def get_stats(period=None, month=None, year=None):
    now = datetime.now()
    today = now.strftime('%Y-%m-%d')
    if month or year:
        target_month = int(month) if month else now.month
        target_year = int(year) if year else now.year
        if target_month < 1 or target_month > 12:
            target_month = now.month
        _, last_day = calendar.monthrange(target_year, target_month)
        month_start = f'{target_year:04d}-{target_month:02d}-01'
        month_end = f'{target_year:04d}-{target_month:02d}-{last_day:02d}'
    elif period == 7:
        target_month = now.month
        target_year = now.year
        start = now - timedelta(days=(now.weekday() + 1) % 7)
        month_start = start.strftime('%Y-%m-%d')
        month_end = today
    elif period == 30:
        target_month = now.month
        target_year = now.year
        month_start = now.strftime('%Y-%m-01')
        month_end = today
    elif period == 90:
        target_month = now.month
        target_year = now.year
        m = now.month - 3
        y = now.year
        while m < 1:
            m += 12
            y -= 1
        month_start = f'{y}-{m:02d}-01'
        month_end = today
    elif period == 365:
        target_month = now.month
        target_year = now.year
        month_start = f'{now.year}-01-01'
        month_end = today
    else:
        target_month = now.month
        target_year = now.year
        _, last_day = calendar.monthrange(target_year, target_month)
        month_start = f'{target_year:04d}-{target_month:02d}-01'
        month_end = f'{target_year:04d}-{target_month:02d}-{last_day:02d}'

    if target_month == 1:
        prev_m = 12
        prev_y = target_year - 1
    else:
        prev_m = target_month - 1
        prev_y = target_year
    _, prev_last_day = calendar.monthrange(prev_y, prev_m)
    prev_month_start = f'{prev_y:04d}-{prev_m:02d}-01'
    prev_month_last = f'{prev_y:04d}-{prev_m:02d}-{prev_last_day:02d}'

    # Agendamentos (operacional / por cliente)
    today_appts = get_db().table(TABLE_APPOINTMENTS).select('*').eq('appointment_date', today).order('appointment_time').execute()
    today_count = len(today_appts.data)
    today_pending = sum(1 for a in today_appts.data if a['status'] == 'pending')

    month_appts = get_db().table(TABLE_APPOINTMENTS).select('*').gte('appointment_date', month_start).lte('appointment_date', month_end).execute()
    month_appointments_count = len(month_appts.data)

    month_clients = get_db().table(TABLE_APPOINTMENTS).select('client_id').gte('appointment_date', month_start).lte('appointment_date', month_end).execute()
    month_clients_count = len(set(a['client_id'] for a in month_clients.data if a.get('client_id')))

    # Receita financeira (lançamentos — independente de clientes cadastrados)
    month_income = _income_transactions(month_start, month_end)
    if target_year == now.year and target_month == now.month:
        today_income = [t for t in month_income if t.get('date') == today]
    else:
        today_income = _income_transactions(today, today)
    today_revenue = _sum_income(today_income)
    month_revenue = _sum_income(month_income)

    month_trans = get_db().table(TABLE_TRANSACTIONS).select('*').gte('date', month_start).lte('date', month_end).execute()
    month_expenses = sum(_tx_amount(t) for t in month_trans.data if t['type'] == 'expense')

    # Total revenue all & avg_ticket via direct aggregate
    tx_agg = _run("SELECT COUNT(*) AS cnt, COALESCE(SUM(amount), 0) AS total FROM transactions WHERE type = 'income'")
    income_cnt = tx_agg[0]['cnt'] if tx_agg else 0
    total_revenue_all = float(tx_agg[0]['total'] if tx_agg else 0)
    avg_ticket = round(total_revenue_all / income_cnt, 2) if income_cnt > 0 else 0

    # Active clients
    active = get_db().table(TABLE_CLIENTS).select('id', count='exact').execute()
    active_clients = active.count or 0

    # Meta
    meta_result = get_db().table(TABLE_SETTINGS).select('value').eq('key', 'meta_mensal').limit(1).execute()
    meta_mensal = 7000
    meta_pct = 0
    if meta_result.data:
        meta_mensal = float(meta_result.data[0]['value'])
        meta_pct = round((month_revenue / meta_mensal) * 100, 1) if meta_mensal > 0 else 0

    # Top clientes — métrica agregada por cliente
    top_clients_rows = _rows(_run(
        "SELECT c.id, c.name, c.avatar_initials, c.avatar_bg, c.avatar_color, "
        "COUNT(a.id) AS visits, "
        "COALESCE(SUM(a.price), 0) AS total_spent, "
        "MAX(a.appointment_date) AS last_visit "
        "FROM clients c "
        "JOIN appointments a ON a.client_id = c.id "
        "WHERE a.status = %s AND a.appointment_date >= %s AND a.appointment_date <= %s "
        "GROUP BY c.id, c.name, c.avatar_initials, c.avatar_bg, c.avatar_color "
        "ORDER BY total_spent DESC "
        "LIMIT 5",
        (REVENUE_APPOINTMENT_STATUS, month_start, month_end)
    ))
    top_clients = [
        {
            'id': r['id'],
            'name': r['name'],
            'avatar_initials': r.get('avatar_initials') or (r['name'][:2].upper() if r.get('name') else '??'),
            'avatar_bg': r.get('avatar_bg') or '#e8f2fc',
            'avatar_color': r.get('avatar_color') or '#1a5fab',
            'visits': int(r['visits']),
            'total_spent': float(r['total_spent']),
            'last_visit': r['last_visit']
        }
        for r in top_clients_rows
    ]

    # Today appointments with client names in a single query
    today_rows = _rows(_run(
        "SELECT a.*, COALESCE(c.name, '(Cliente removido)') AS client_name, COALESCE(c.phone, '') AS client_phone "
        "FROM appointments a "
        "LEFT JOIN clients c ON c.id = a.client_id "
        "WHERE a.appointment_date = %s "
        "ORDER BY a.appointment_time",
        (today,)
    ))
    today_full = []
    for a in today_rows:
        a['appointment_time'] = a['appointment_time'][:5] if a.get('appointment_time') and len(a['appointment_time']) >= 5 else (a.get('appointment_time') or '')
        today_full.append(a)

    # Month appointments with times (for heatmap)
    month_full = []
    for a in month_appts.data:
        if a.get('appointment_time'):
            a['appointment_time'] = a['appointment_time'][:5]
        month_full.append({
            'appointment_date': a.get('appointment_date', ''),
            'appointment_time': a.get('appointment_time', ''),
            'status': a.get('status', ''),
            'service': a.get('service', ''),
            'price': a.get('price', 0),
        })

    # Serviços mais usados — por clientes ativos (agendamentos concluídos)
    svc_counts = {}
    for a in month_appts.data:
        if not counts_as_revenue(a['status']):
            continue
        svc = a.get('service') or 'Outros'
        svc_counts[svc] = svc_counts.get(svc, 0) + 1
    total_svc = sum(svc_counts.values()) or 1
    service_breakdown = sorted([
        {'name': k, 'count': v, 'pct': round(v / total_svc * 100, 1)}
        for k, v in svc_counts.items()
    ], key=lambda x: -x['count'])[:5]

    # Receita por serviço — financeiro (lançamentos)
    svc_revenue = {}
    for t in month_income:
        svc = _transaction_service_name(t)
        svc_revenue[svc] = svc_revenue.get(svc, 0) + _tx_amount(t)
    total_svc_rev = sum(svc_revenue.values()) or 1
    service_revenue_breakdown = sorted([
        {'name': k, 'revenue': v, 'pct': round(v / total_svc_rev * 100, 1)}
        for k, v in svc_revenue.items()
    ], key=lambda x: -x['revenue'])[:5]

    # Receita semanal / diária — financeiro
    weekly_rev = {}
    for t in month_income:
        try:
            d = datetime.strptime(t['date'], '%Y-%m-%d')
            week = (d.day - 1) // 7
            weekly_rev[week] = weekly_rev.get(week, 0) + _tx_amount(t)
        except (ValueError, TypeError):
            pass
    weekly_revenue = [weekly_rev.get(i, 0) for i in range(max(weekly_rev.keys()) + 1)] if weekly_rev else []

    day_names_pt = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab']
    daily_rev = {}
    daily_exp = {}
    for t in month_income:
        daily_rev[t['date']] = daily_rev.get(t['date'], 0) + _tx_amount(t)
    for t in month_trans.data:
        if t['type'] == 'expense':
            daily_exp[t['date']] = daily_exp.get(t['date'], 0) + _tx_amount(t)
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
    pix = get_db().table(TABLE_TRANSACTIONS).select('id', count='exact').eq('type', 'income').eq('payment_method', 'Pix').gte('date', month_start).lte('date', month_end).execute()
    pix_pending = pix.count or 0

    # Recent transactions
    recent_tx = get_db().table(TABLE_TRANSACTIONS).select('*').gte('date', month_start).lte('date', month_end).order('date', desc=True).order('id', desc=True).limit(10).execute()
    recent_transactions = []
    for t in recent_tx.data:
        if not t.get('client_name'):
            t['client_name'] = _transaction_client_name(t)
        recent_transactions.append(t)

    # Expenses by category
    exp_cat = get_db().table(TABLE_TRANSACTIONS).select('category, amount').eq('type', 'expense').gte('date', month_start).lte('date', month_end).execute()
    cat_totals = {}
    for t in exp_cat.data:
        cat_totals[t['category'] or 'Outros'] = cat_totals.get(t['category'] or 'Outros', 0) + t['amount']
    total_exp = sum(cat_totals.values()) or 1
    expenses_by_category = [
        {'category': cat, 'amount': val, 'pct': round(val / total_exp * 100, 1)}
        for cat, val in sorted(cat_totals.items(), key=lambda x: -x[1])
    ]

    prev_month_last = (now.replace(day=1) - timedelta(days=1)).strftime('%Y-%m-%d')
    prev_income = _income_transactions(prev_month_start, prev_month_last)
    month_revenue_prev = _sum_income(prev_income)

    # Inactive clients (30+ days since last visit or never visited)
    inactive_count = 0
    inactive_revenue = 0
    try:
        v_clients = get_db().table('v_clients').select('id,total_spent,last_visit').execute()
        thirty_days_ago = (now - timedelta(days=30)).strftime('%Y-%m-%d')
        for cl in v_clients.data:
            if not cl.get('last_visit') or cl['last_visit'] < thirty_days_ago:
                inactive_count += 1
                inactive_revenue += cl['total_spent'] or 0
    except Exception:
        pass

    # Future pending appointments needing confirmation
    future_pending = get_db().table(TABLE_APPOINTMENTS).select('id', count='exact').eq('status', 'pending').gte('appointment_date', today).execute()
    pending_future_count = future_pending.count or 0

    month_label_pt = {
        1: 'Janeiro', 2: 'Fevereiro', 3: 'Março', 4: 'Abril',
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
        'month_label': month_label_pt.get(target_month, ''),
        'month_year': target_year,
        'selected_month': target_month,
        'selected_year': target_year,
        'month_clients': month_clients_count,
        'weekly_revenue': weekly_revenue,
        'service_breakdown': service_breakdown,
        'service_revenue_breakdown': service_revenue_breakdown,
        'meta_mensal': meta_mensal,
        'meta_pct': meta_pct,
        'pix_pending': pix_pending,
        'total_revenue_all': total_revenue_all,
        'month_appointments_count': month_appointments_count,
        'top_clients': top_clients,
        'today_appointments': today_full,
        'daily_breakdown': daily_breakdown,
        'recent_transactions': recent_transactions,
        'expenses_by_category': expenses_by_category,
        'month_revenue_prev': month_revenue_prev,
        'month_appointments': month_full,
        'inactive_clients': inactive_count,
        'inactive_revenue': inactive_revenue,
        'pending_future': pending_future_count,
    }


# ══════════════════════════════════════════════════════════════════════════
# Usuários
# ══════════════════════════════════════════════════════════════════════════


def all_users():
    try:
        r = get_db().table(TABLE_USERS).select('id,name,email,phone,role,created_at').order('name').execute()
        return r.data
    except Exception:
        return []


def get_user(user_id):
    try:
        r = get_db().table(TABLE_USERS).select('*').eq('id', user_id).limit(1).execute()
        return r.data[0] if r.data else None
    except Exception:
        return None


def get_user_by_email(email):
    if not email:
        return None
    try:
        clean = email.strip().lower()
        rows = _rows(_run("SELECT * FROM users WHERE LOWER(TRIM(email)) = %s LIMIT 1", (clean,)))
        return rows[0] if rows else None
    except Exception:
        return None


def create_user(name, email, password_hash, phone='', role='admin'):
    try:
        r = get_db().table(TABLE_USERS).insert({
            'name': name,
            'email': email,
            'phone': phone,
            'password_hash': password_hash,
            'role': role,
        }).execute()
        return r.data[0] if r.data else None
    except Exception:
        return None


def update_user(user_id, data):
    try:
        get_db().table(TABLE_USERS).update(data).eq('id', user_id).execute()
        r = get_db().table(TABLE_USERS).select('id,name,email,phone,role,created_at').eq('id', user_id).single().execute()
        return r.data
    except Exception:
        return None


def delete_user(user_id):
    try:
        get_db().table(TABLE_USERS).delete().eq('id', user_id).execute()
    except Exception:
        pass


# ══════════════════════════════════════════════════════════════════════════
# Notifications
# ══════════════════════════════════════════════════════════════════════════


def create_notification(notif_type, title, message, related_id=None, related_type=''):
    try:
        r = get_db().table(TABLE_NOTIFICATIONS).insert({
            'type': notif_type,
            'title': title,
            'message': message,
            'related_id': related_id,
            'related_type': related_type,
        }).execute()
        return r.data[0] if r.data else None
    except Exception:
        return None


def get_notifications(limit=20):
    try:
        r = get_db().table(TABLE_NOTIFICATIONS).select('*').order('created_at', desc=True).limit(limit).execute()
        return r.data
    except Exception:
        return []


def unread_notifications_count():
    try:
        r = get_db().table(TABLE_NOTIFICATIONS).select('id', count='exact').eq('read', False).execute()
        return r.count or 0
    except Exception:
        return 0


def mark_notification_read(notif_id):
    try:
        get_db().table(TABLE_NOTIFICATIONS).update({'read': True}).eq('id', notif_id).execute()
    except Exception:
        pass


def mark_all_notifications_read():
    try:
        get_db().table(TABLE_NOTIFICATIONS).update({'read': True}).eq('read', False).execute()
    except Exception:
        pass


# ══════════════════════════════════════════════════════════════════════════
# Integrations
# ══════════════════════════════════════════════════════════════════════════


def list_integrations():
    try:
        r = get_db().table(TABLE_INTEGRATIONS).select('*').order('created_at').execute()
        return r.data
    except Exception:
        return []


def get_integration(integ_id):
    try:
        r = get_db().table(TABLE_INTEGRATIONS).select('*').eq('id', integ_id).limit(1).execute()
        return r.data[0] if r.data else None
    except Exception:
        return None


def create_integration(name, integ_type, config=None, enabled=True):
    try:
        r = get_db().table(TABLE_INTEGRATIONS).insert({
            'name': name,
            'type': integ_type,
            'config': config or {},
            'enabled': enabled,
        }).execute()
        return r.data[0] if r.data else None
    except Exception:
        return None


def update_integration(integ_id, data):
    try:
        get_db().table(TABLE_INTEGRATIONS).update(data).eq('id', integ_id).execute()
        r = get_db().table(TABLE_INTEGRATIONS).select('*').eq('id', integ_id).limit(1).execute()
        return r.data[0] if r.data else None
    except Exception:
        return None


def delete_integration(integ_id):
    try:
        get_db().table(TABLE_INTEGRATIONS).delete().eq('id', integ_id).execute()
    except Exception:
        pass


# ══════════════════════════════════════════════════════════════════════════
# Business Hours
# ══════════════════════════════════════════════════════════════════════════

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


def _criar_tabela_business_hours():
    global _BH_ALERTADO
    if _BH_ALERTADO:
        return
    _BH_ALERTADO = True
    print("[DB] Tabela 'business_hours' não encontrada — o schema será inicializado automaticamente.")


def _migrate_business_hours():
    try:
        r = get_db().table(TABLE_BUSINESS_HOURS).select('id').limit(1).execute()
        if r.data:
            return
    except Exception:
        _criar_tabela_business_hours()
        return
    try:
        s = get_settings()
        raw = s.get('business_hours', '')
        if raw:
            data = json.loads(raw)
            rows = [{'day': k, 'open': v.get('open', ''), 'close': v.get('close', ''), 'closed': v.get('closed', False)} for k, v in data.items()]
            get_db().table(TABLE_BUSINESS_HOURS).upsert(rows, on_conflict='day').execute()
            get_db().table(TABLE_SETTINGS).delete().eq('key', 'business_hours').execute()
    except Exception:
        pass


def load_business_hours():
    try:
        r = get_db().table(TABLE_BUSINESS_HOURS).select('day,open,close,closed').execute()
        if r.data:
            return {row['day']: {'open': row['open'], 'close': row['close'], 'closed': row['closed']} for row in r.data}
    except Exception:
        _criar_tabela_business_hours()
    return dict(DEFAULT_HOURS)


def save_business_hours(data):
    for day_key, info in data.items():
        try:
            get_db().table(TABLE_BUSINESS_HOURS).upsert({
                'day': day_key,
                'open': info.get('open', ''),
                'close': info.get('close', ''),
                'closed': info.get('closed', False),
            }, on_conflict='day').execute()
        except Exception:
            _criar_tabela_business_hours()
            raise RuntimeError(
                f"Tabela 'business_hours' não existe. O schema deveria ter sido criado automaticamente."
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
