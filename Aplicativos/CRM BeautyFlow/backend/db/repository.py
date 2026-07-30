"""
Camada de acesso a dados. Substitui todas as chamadas ao SDK do Supabase.
Cada funcao corresponde a uma operacao real identificada no codigo original
(routes/*.py + database.py). Sem logica de negocio aqui - isso fica em
db/database.py.
"""
import datetime
import psycopg.rows
from psycopg.types.json import Jsonb
from db.connection import get_conn


def _make_json_safe(row):
    if row is None:
        return None
    for k, v in list(row.items()):
        if isinstance(v, (datetime.datetime, datetime.date, datetime.time)):
            row[k] = v.isoformat()
        elif isinstance(v, bytes):
            row[k] = v.decode('utf-8', errors='replace')
    return row


def _json_safe_all(rows):
    if rows is None:
        return None
    if isinstance(rows, list):
        return [_make_json_safe(r) for r in rows]
    return _make_json_safe(rows)


def _dict_cursor(conn):
    return conn.cursor(row_factory=psycopg.rows.dict_row)


def _query(sql, params=None):
    with get_conn() as conn:
        with _dict_cursor(conn) as cur:
            cur.execute(sql, params or ())
            return _json_safe_all(cur.fetchall())


def _query_one(sql, params=None):
    with get_conn() as conn:
        with _dict_cursor(conn) as cur:
            cur.execute(sql, params or ())
            return _json_safe_all(cur.fetchone())


def _insert(table, payload: dict):
    columns = list(payload.keys())
    values = list(payload.values())
    placeholders = ", ".join(["%s"] * len(values))
    col_list = ", ".join(columns)
    with get_conn() as conn:
        with _dict_cursor(conn) as cur:
            cur.execute(
                f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) RETURNING *",
                values,
            )
            conn.commit()
            return _make_json_safe(cur.fetchone())


def _update(table, record_id, data: dict, id_column='id'):
    if not data:
        return None
    set_clause = ", ".join(f"{k} = %s" for k in data.keys())
    values = list(data.values()) + [record_id]
    with get_conn() as conn:
        with _dict_cursor(conn) as cur:
            cur.execute(
                f"UPDATE {table} SET {set_clause} WHERE {id_column} = %s RETURNING *",
                values,
            )
            conn.commit()
            return _make_json_safe(cur.fetchone())


def _delete(table, record_id, id_column='id'):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(f"DELETE FROM {table} WHERE {id_column} = %s", (record_id,))
            conn.commit()
            return cur.rowcount > 0


# clients

def list_clients_with_stats():
    return _query("SELECT * FROM v_clients ORDER BY name")


def list_clients_basic():
    return _query("SELECT id, name, avatar_initials, avatar_bg, avatar_color FROM clients")


def list_clients_view_stats():
    return _query("SELECT id, total_spent, last_visit FROM v_clients")


def get_client_with_stats(client_id):
    return _query_one("SELECT * FROM v_clients WHERE id = %s", (client_id,))


def get_client_raw(client_id):
    return _query_one("SELECT * FROM clients WHERE id = %s", (client_id,))


def count_clients():
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM clients")
            return cur.fetchone()[0]


def list_client_appointments(client_id):
    return _query(
        """SELECT * FROM appointments
           WHERE client_id = %s
           ORDER BY appointment_date DESC, appointment_time DESC""",
        (client_id,),
    )


def create_client(payload: dict):
    return _insert('clients', payload)


def update_client(client_id, data: dict):
    return _update('clients', client_id, data)


def delete_client(client_id):
    return _delete('clients', client_id)


# appointments

def get_appointment_with_client(appt_id):
    return _query_one(
        """SELECT a.*, c.name AS client_name, c.phone AS client_phone
           FROM appointments a
           LEFT JOIN clients c ON c.id = a.client_id
           WHERE a.id = %s""",
        (appt_id,),
    )


def get_appointment_raw(appt_id):
    return _query_one("SELECT * FROM appointments WHERE id = %s", (appt_id,))


def list_appointments(date=None, client_id=None, status=None, date_from=None, date_to=None):
    sql = """SELECT a.*, c.name AS client_name, c.phone AS client_phone
             FROM appointments a
             LEFT JOIN clients c ON c.id = a.client_id
             WHERE 1=1"""
    params = []
    if date:
        sql += " AND a.appointment_date = %s"; params.append(date)
    if date_from:
        sql += " AND a.appointment_date >= %s"; params.append(date_from)
    if date_to:
        sql += " AND a.appointment_date <= %s"; params.append(date_to)
    if client_id:
        sql += " AND a.client_id = %s"; params.append(client_id)
    if status:
        sql += " AND a.status = %s"; params.append(status)
    sql += " ORDER BY a.appointment_date, a.appointment_time"
    return _query(sql, params)


def list_appointments_by_date_active(date_str):
    return _query(
        """SELECT appointment_time, duration, service
           FROM appointments
           WHERE appointment_date = %s AND status != 'cancelled'""",
        (date_str,),
    )


def list_appointment_ids_by_payment_status(payment_status):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM appointments WHERE payment_status = %s", (payment_status,))
            return [row[0] for row in cur.fetchall()]


def count_pending_future_appointments(from_date):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM appointments WHERE status = 'pending' AND appointment_date >= %s",
                (from_date,),
            )
            return cur.fetchone()[0]


def top_clients_by_revenue(date_from, date_to, limit=5):
    return _query("""
        SELECT c.id, c.name, c.avatar_initials, c.avatar_bg, c.avatar_color,
               COUNT(a.id) AS visits,
               COALESCE(SUM(a.price), 0) AS total_spent,
               MAX(a.appointment_date) AS last_visit
        FROM appointments a
        JOIN clients c ON c.id = a.client_id
        WHERE a.payment_status = 'paid'
          AND a.appointment_date >= %s AND a.appointment_date <= %s
        GROUP BY c.id, c.name, c.avatar_initials, c.avatar_bg, c.avatar_color
        ORDER BY total_spent DESC
        LIMIT %s
    """, (date_from, date_to, limit))


def create_appointment(payload: dict):
    return _insert('appointments', payload)


def update_appointment(appt_id, data: dict):
    return _update('appointments', appt_id, data)


def delete_appointment(appt_id):
    return _delete('appointments', appt_id)


# transactions

def list_transactions(date_from=None, date_to=None, tx_type=None, limit=None):
    sql = "SELECT * FROM transactions WHERE 1=1"
    params = []
    if date_from:
        sql += " AND date >= %s"; params.append(date_from)
    if date_to:
        sql += " AND date <= %s"; params.append(date_to)
    if tx_type:
        sql += " AND type = %s"; params.append(tx_type)
    sql += " ORDER BY date DESC, id DESC"
    if limit:
        sql += " LIMIT %s"; params.append(limit)
    return _query(sql, params)


def list_income_transactions(date_from=None, date_to=None):
    return list_transactions(date_from=date_from, date_to=date_to, tx_type='income')


def get_transaction(tx_id):
    return _query_one("SELECT * FROM transactions WHERE id = %s", (tx_id,))


def insert_transaction(payload: dict):
    return _insert('transactions', payload)


def update_transaction(tx_id, data: dict):
    return _update('transactions', tx_id, data)


def delete_transaction(tx_id):
    return _delete('transactions', tx_id)


def delete_transactions_by_appointment(appt_id, tx_type='income'):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM transactions WHERE appointment_id = %s AND type = %s",
                (appt_id, tx_type),
            )
            conn.commit()
            return cur.rowcount


def get_income_transaction_by_appointment(appt_id):
    return _query_one(
        "SELECT * FROM transactions WHERE appointment_id = %s AND type = 'income' LIMIT 1",
        (appt_id,),
    )


def expenses_by_category(date_from):
    return _query(
        "SELECT category, amount FROM transactions WHERE type = 'expense' AND date >= %s",
        (date_from,),
    )


def pix_pending_count(date_from):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM transactions WHERE type = 'income' AND payment_method = 'Pix' AND date >= %s",
                (date_from,),
            )
            return cur.fetchone()[0]


# services

def list_services():
    return _query("SELECT * FROM services ORDER BY name")


def list_services_with_buffer():
    return _query("SELECT name, buffer FROM services")


def get_service_by_name(name):
    return _query_one("SELECT * FROM services WHERE name = %s LIMIT 1", (name,))


def get_service_by_id(svc_id):
    return _query_one("SELECT * FROM services WHERE id = %s LIMIT 1", (svc_id,))


def create_service(payload: dict):
    return _insert('services', payload)


def update_service(svc_id, data: dict):
    return _update('services', svc_id, data)


def delete_service(svc_id):
    return _delete('services', svc_id)


# settings

def get_settings():
    rows = _query("SELECT key, value FROM settings")
    return {row['key']: row['value'] for row in rows}


def update_setting(key, value):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO settings (key, value) VALUES (%s, %s)
                   ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value""",
                (key, str(value)),
            )
            conn.commit()


# business_hours

def load_business_hours():
    rows = _query("SELECT day, open, close, closed FROM business_hours")
    return {
        row['day']: {'open': row['open'], 'close': row['close'], 'closed': row['closed']}
        for row in rows
    }


def save_business_hours(data: dict):
    with get_conn() as conn:
        with conn.cursor() as cur:
            for day_key, info in data.items():
                cur.execute(
                    """INSERT INTO business_hours (day, open, close, closed)
                       VALUES (%s, %s, %s, %s)
                       ON CONFLICT (day) DO UPDATE
                       SET open = EXCLUDED.open, close = EXCLUDED.close, closed = EXCLUDED.closed""",
                    (day_key, info.get('open', ''), info.get('close', ''), info.get('closed', False)),
                )
            conn.commit()


# notifications

def create_notification(notif_type, title, message, related_id=None, related_type=''):
    return _insert('notifications', {
        'type': notif_type, 'title': title, 'message': message,
        'related_id': related_id, 'related_type': related_type,
    })


def get_notifications(limit=20):
    return _query("SELECT * FROM notifications ORDER BY created_at DESC LIMIT %s", (limit,))


def unread_notifications_count():
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM notifications WHERE read = FALSE")
            return cur.fetchone()[0]


def mark_notification_read(notif_id):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE notifications SET read = TRUE WHERE id = %s", (notif_id,))
            conn.commit()


def mark_all_notifications_read():
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE notifications SET read = TRUE WHERE read = FALSE")
            conn.commit()


def exists_notification_of_type(notif_type):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM notifications WHERE type = %s LIMIT 1", (notif_type,))
            return cur.fetchone() is not None


# integrations

def list_integrations():
    return _query("SELECT * FROM integrations ORDER BY created_at")


def get_integration(integ_id):
    return _query_one("SELECT * FROM integrations WHERE id = %s LIMIT 1", (integ_id,))


def create_integration(name, integ_type, config=None, enabled=True):
    with get_conn() as conn:
        with _dict_cursor(conn) as cur:
            cur.execute(
                """INSERT INTO integrations (name, type, config, enabled)
                   VALUES (%s, %s, %s, %s) RETURNING *""",
                (name, integ_type, Jsonb(config or {}), enabled),
            )
            conn.commit()
            return _make_json_safe(cur.fetchone())


def update_integration(integ_id, data: dict):
    payload = dict(data)
    if 'config' in payload:
        payload['config'] = Jsonb(payload['config'])
    return _update('integrations', integ_id, payload)


def delete_integration(integ_id):
    return _delete('integrations', integ_id)


# users

def all_users():
    return _query("SELECT id, name, email, phone, role, created_at FROM users ORDER BY name")


def get_user(user_id):
    return _query_one("SELECT * FROM users WHERE id = %s LIMIT 1", (user_id,))


def get_user_by_email(email):
    return _query_one("SELECT * FROM users WHERE email = %s LIMIT 1", (email,))


def create_user(name, email, password_hash, phone='', role='admin'):
    return _insert('users', {
        'name': name, 'email': email, 'phone': phone,
        'password_hash': password_hash, 'role': role,
    })


def update_user(user_id, data: dict):
    row = _update('users', user_id, data)
    if row:
        row.pop('password_hash', None)
    return row


def delete_user(user_id):
    return _delete('users', user_id)
