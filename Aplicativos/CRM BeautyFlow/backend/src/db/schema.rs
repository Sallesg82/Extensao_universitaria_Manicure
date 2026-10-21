use crate::services::auth::hash_password;
use sqlx::{PgPool, Row};
use tracing::{info, warn};

pub const SCHEMA_SQL: &str = r#"
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
    created_at        TIMESTAMPTZ DEFAULT NOW(),
    updated_at        TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_appointments_client ON appointments (client_id);
CREATE INDEX IF NOT EXISTS idx_appointments_date ON appointments (appointment_date);
CREATE INDEX IF NOT EXISTS idx_appointments_status ON appointments (status);
CREATE INDEX IF NOT EXISTS idx_appointments_payment_status ON appointments (payment_status);
CREATE INDEX IF NOT EXISTS idx_appointments_client_date ON appointments (client_id, appointment_date);

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
    type        TEXT NOT NULL CHECK(type IN ('webhook', 'n8n', 'whatsapp', 'waha')),
    config      JSONB DEFAULT '{}',
    enabled     BOOLEAN DEFAULT TRUE,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_integrations_type ON integrations (type);
CREATE INDEX IF NOT EXISTS idx_integrations_enabled ON integrations (enabled);

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

CREATE TABLE IF NOT EXISTS metas (
    id          SERIAL PRIMARY KEY,
    mes         VARCHAR(7) NOT NULL UNIQUE,
    meta        NUMERIC(12, 2) NOT NULL DEFAULT 7000.00,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS products (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    category    TEXT DEFAULT 'esmaltes',
    qty         INTEGER DEFAULT 0,
    price       REAL DEFAULT 0,
    min_qty     INTEGER DEFAULT 5,
    missing     BOOLEAN DEFAULT false,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

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
"#;

pub async fn init_schema(pool: &PgPool) {
    if let Err(e) = sqlx::raw_sql(SCHEMA_SQL).execute(pool).await {
        warn!("[DB] Aviso ao aplicar schema base: {}", e);
    }

    let alter_sql = r#"
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'integrations_type_check' AND table_name = 'integrations'
      ) THEN
        ALTER TABLE integrations DROP CONSTRAINT integrations_type_check;
        ALTER TABLE integrations ADD CONSTRAINT integrations_type_check CHECK(type IN ('webhook', 'n8n', 'whatsapp', 'waha'));
      END IF;
    END $$;
    DELETE FROM integrations WHERE type = 'google_calendar';
    ALTER TABLE appointments DROP COLUMN IF EXISTS google_event_id;
    ALTER TABLE appointments DROP COLUMN IF EXISTS google_html_link;
    DELETE FROM settings WHERE key IN ('google_credentials', 'google_client_id', 'google_client_secret');
    "#;
    let _ = sqlx::raw_sql(alter_sql).execute(pool).await;

    init_realtime_triggers(pool).await;
    ensure_admin_user(pool).await;
    ensure_default_data(pool).await;
    ensure_metas_table(pool).await;
    backfill_appointment_income_transactions(pool).await;
}

pub async fn ensure_admin_user(pool: &PgPool) -> bool {
    let row = sqlx::query("SELECT COUNT(*) AS total FROM users")
        .fetch_one(pool)
        .await;

    if let Ok(r) = row {
        let total: i64 = r.get("total");
        if total == 0 {
            let pw_hash = hash_password("admin");
            let _ = sqlx::query(
                "INSERT INTO users (name, email, phone, password_hash, role) VALUES ($1, $2, $3, $4, $5)"
            )
            .bind("Administrador")
            .bind("admin")
            .bind("")
            .bind(&pw_hash)
            .bind("admin")
            .execute(pool)
            .await;
            info!("[DB] Usuário padrão criado: admin / admin");
            return true;
        }
    }
    false
}

#[allow(dead_code)]
pub async fn reset_admin_password(pool: &PgPool, new_pass: &str) -> Result<(), sqlx::Error> {
    let pw_hash = hash_password(new_pass);
    sqlx::query("UPDATE users SET password_hash = $1 WHERE email = $2")
        .bind(&pw_hash)
        .bind("admin")
        .execute(pool)
        .await?;
    info!("[DB] Senha do admin redefinida com sucesso.");
    Ok(())
}

pub async fn ensure_metas_table(pool: &PgPool) {
    let sql = r#"
    CREATE TABLE IF NOT EXISTS public.metas (
        id SERIAL PRIMARY KEY,
        mes VARCHAR(7) NOT NULL,
        meta NUMERIC(12, 2) NOT NULL DEFAULT 7000.00,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
        CONSTRAINT metas_mes_unique UNIQUE (mes)
    );

    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'metas') THEN
        DROP TRIGGER IF EXISTS trg_realtime_metas ON metas;
        CREATE TRIGGER trg_realtime_metas
          AFTER INSERT OR UPDATE OR DELETE ON metas
          FOR EACH ROW EXECUTE FUNCTION notify_pgevents();
      END IF;
    END $$;
    "#;
    let _ = sqlx::raw_sql(sql).execute(pool).await;
}

pub async fn ensure_default_data(pool: &PgPool) {
    let _ = sqlx::raw_sql(r#"
        INSERT INTO business_hours (day, open, close, closed) VALUES
            ('segunda', '08:00', '18:00', false),
            ('terca',   '08:00', '18:00', false),
            ('quarta',  '08:00', '18:00', false),
            ('quinta',  '08:00', '18:00', false),
            ('sexta',   '08:00', '18:00', false),
            ('sabado',  '08:00', '13:00', false),
            ('domingo', '',      '',      true)
        ON CONFLICT (day) DO NOTHING;

        INSERT INTO services (name, duration, buffer, price, color) VALUES
            ('Manicure Tradicional', 45, 15, 45.0, '#E07A5F'),
            ('Pedicure Tradicional', 45, 15, 50.0, '#3D405B'),
            ('Combo Manicure + Pedicure', 80, 15, 85.0, '#81B29A'),
            ('Alongamento em Gel', 120, 15, 150.0, '#F2CC8F'),
            ('Spa dos Pés', 60, 15, 70.0, '#D4A373'),
            ('Esmaltação em Gel', 60, 15, 65.0, '#C084FC')
        ON CONFLICT (name) DO NOTHING;

        INSERT INTO settings (key, value) VALUES
            ('meta_mensal', '7000')
        ON CONFLICT (key) DO NOTHING;

        INSERT INTO products (name, category, qty, price, min_qty, missing) VALUES
            ('Esmalte Risqué Cremoso', 'esmaltes', 24, 5.50, 10, false),
            ('Gel Construtor Vòlia Classic', 'esmaltes', 6, 65.0, 3, false),
            ('Óleo Nutritivo de Cutícula', 'cuidados', 4, 18.0, 5, false),
            ('Luvas Nitrílicas Rosa (cx 100un)', 'descartaveis', 2, 38.0, 4, false),
            ('Algodão Hidrófilo Rolete', 'descartaveis', 0, 8.50, 5, true),
            ('Removedor Sem Acetona 500ml', 'quimicos', 8, 16.0, 4, false),
            ('Álcool Isopropílico 70% 1L', 'quimicos', 3, 22.0, 3, false),
            ('Alicate de Cutícula Mundial 777', 'equipamentos', 7, 42.0, 3, false),
            ('Lixas Bloco Fecha Poros (pct 10)', 'equipamentos', 0, 14.0, 4, true),
            ('Toalhas Descartáveis Manicure (pct 50)', 'descartaveis', 12, 28.0, 5, false)
        ON CONFLICT DO NOTHING;
    "#).execute(pool).await;
}

pub async fn init_realtime_triggers(pool: &PgPool) {
    let sql = r#"
    CREATE OR REPLACE FUNCTION notify_pgevents() RETURNS trigger AS $$
    DECLARE
      rec_id text;
      payload text;
    BEGIN
      IF (TG_OP = 'DELETE') THEN
        BEGIN
          rec_id := OLD.id::text;
        EXCEPTION WHEN OTHERS THEN
          rec_id := NULL;
        END;
      ELSE
        BEGIN
          rec_id := NEW.id::text;
        EXCEPTION WHEN OTHERS THEN
          rec_id := NULL;
        END;
      END IF;

      payload := json_build_object(
        'table', TG_TABLE_NAME,
        'action', TG_OP,
        'id', rec_id
      )::text;

      PERFORM pg_notify('pgevents', payload);
      RETURN COALESCE(NEW, OLD);
    END;
    $$ LANGUAGE plpgsql;

    DROP TRIGGER IF EXISTS trg_realtime_appointments ON appointments;
    CREATE TRIGGER trg_realtime_appointments
      AFTER INSERT OR UPDATE OR DELETE ON appointments
      FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

    DROP TRIGGER IF EXISTS trg_realtime_transactions ON transactions;
    CREATE TRIGGER trg_realtime_transactions
      AFTER INSERT OR UPDATE OR DELETE ON transactions
      FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

    DROP TRIGGER IF EXISTS trg_realtime_clients ON clients;
    CREATE TRIGGER trg_realtime_clients
      AFTER INSERT OR UPDATE OR DELETE ON clients
      FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

    DROP TRIGGER IF EXISTS trg_realtime_services ON services;
    CREATE TRIGGER trg_realtime_services
      AFTER INSERT OR UPDATE OR DELETE ON services
      FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

    DROP TRIGGER IF EXISTS trg_realtime_settings ON settings;
    CREATE TRIGGER trg_realtime_settings
      AFTER INSERT OR UPDATE OR DELETE ON settings
      FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

    DROP TRIGGER IF EXISTS trg_realtime_business_hours ON business_hours;
    CREATE TRIGGER trg_realtime_business_hours
      AFTER INSERT OR UPDATE OR DELETE ON business_hours
      FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

    DROP TRIGGER IF EXISTS trg_realtime_notifications ON notifications;
    CREATE TRIGGER trg_realtime_notifications
      AFTER INSERT OR UPDATE OR DELETE ON notifications
      FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

    DROP TRIGGER IF EXISTS trg_realtime_users ON users;
    CREATE TRIGGER trg_realtime_users
      AFTER INSERT OR UPDATE OR DELETE ON users
      FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'metas') THEN
        DROP TRIGGER IF EXISTS trg_realtime_metas ON metas;
        CREATE TRIGGER trg_realtime_metas
          AFTER INSERT OR UPDATE OR DELETE ON metas
          FOR EACH ROW EXECUTE FUNCTION notify_pgevents();
      END IF;

      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'products') THEN
        DROP TRIGGER IF EXISTS trg_realtime_products ON products;
        CREATE TRIGGER trg_realtime_products
          AFTER INSERT OR UPDATE OR DELETE ON products
          FOR EACH ROW EXECUTE FUNCTION notify_pgevents();
      END IF;
    END $$;
    "#;

    if let Err(e) = sqlx::raw_sql(sql).execute(pool).await {
        warn!("[DB] Aviso ao instalar triggers de realtime: {}", e);
    } else {
        info!("[DB] Triggers de realtime instalados com sucesso no PostgreSQL.");
    }
}

pub async fn sync_appointment_income(pool: &PgPool, appt_id: i32) -> Result<Option<i32>, sqlx::Error> {
    let appt_opt = sqlx::query(
        "SELECT a.*, c.name as client_name FROM appointments a LEFT JOIN clients c ON c.id = a.client_id WHERE a.id = $1"
    )
    .bind(appt_id)
    .fetch_optional(pool)
    .await?;

    let appt = match appt_opt {
        Some(a) => a,
        None => return Ok(None),
    };

    let status: String = appt.get("status");
    let price: f32 = appt.get("price");
    let appt_date: chrono::NaiveDate = appt.get("appointment_date");
    let client_id: Option<i32> = appt.get("client_id");
    let client_name = appt.get::<Option<String>, _>("client_name").unwrap_or_else(|| "Cliente".to_string());
    let service: String = appt.get("service");

    let existing = sqlx::query("SELECT id FROM transactions WHERE appointment_id = $1 AND type = 'income' LIMIT 1")
        .bind(appt_id)
        .fetch_optional(pool)
        .await?;

    if status == "done" {
        let desc = format!("{} — {}", service, client_name);
        if let Some(tx_row) = existing {
            let tx_id: i32 = tx_row.get("id");
            sqlx::query(
                r#"
                UPDATE transactions
                SET amount = $1, date = $2, description = $3, category = 'Serviços',
                    client_id = $4, client_name = $5, service = $6
                WHERE id = $7
                "#
            )
            .bind(price)
            .bind(appt_date)
            .bind(&desc)
            .bind(client_id)
            .bind(&client_name)
            .bind(&service)
            .bind(tx_id)
            .execute(pool)
            .await?;
            return Ok(Some(tx_id));
        } else {
            let ins_row = sqlx::query(
                r#"
                INSERT INTO transactions (type, amount, date, description, category, payment_method, appointment_id, client_id, client_name, service)
                VALUES ('income', $1, $2, $3, 'Serviços', '', $4, $5, $6, $7)
                RETURNING id
                "#
            )
            .bind(price)
            .bind(appt_date)
            .bind(&desc)
            .bind(appt_id)
            .bind(client_id)
            .bind(&client_name)
            .bind(&service)
            .fetch_one(pool)
            .await?;
            let tx_id: i32 = ins_row.get("id");
            return Ok(Some(tx_id));
        }
    } else if let Some(tx_row) = existing {
        let tx_id: i32 = tx_row.get("id");
        sqlx::query("DELETE FROM transactions WHERE id = $1")
            .bind(tx_id)
            .execute(pool)
            .await?;
    }

    Ok(None)
}

pub async fn backfill_appointment_income_transactions(pool: &PgPool) {
    let rows = sqlx::query("SELECT id FROM appointments WHERE status = 'done'")
        .fetch_all(pool)
        .await
        .unwrap_or_default();

    for r in rows {
        let id: i32 = r.get("id");
        let has_tx = sqlx::query("SELECT 1 FROM transactions WHERE appointment_id = $1 AND type = 'income' LIMIT 1")
            .bind(id)
            .fetch_optional(pool)
            .await
            .unwrap_or(None);

        if has_tx.is_none() {
            let _ = sync_appointment_income(pool, id).await;
        }
    }
}

pub use init_schema as init_postgres_schema;

