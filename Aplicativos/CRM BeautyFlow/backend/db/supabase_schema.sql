-- ═══════════════════════════════════════════════════════════════
--  BeautyFlow CRM — Schema Completo Supabase (PostgreSQL)
--  ═══════════════════════════════════════════════════════════════
--  1. Execute este SQL no SQL Editor do seu projeto Supabase
--  2. Depois execute os seeds (final deste arquivo)
--  3. Para self-hosted, conecte diretamente no PostgreSQL:
--     psql postgresql://postgres:postgres@localhost:54322/postgres -f supabase_schema.sql
--  ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
--  TRIGGER: atualiza updated_at automaticamente
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════
--  TABELA: clients (clientes do salão)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS clients (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    phone           TEXT NOT NULL,
    email           TEXT DEFAULT '',
    avatar_initials TEXT NOT NULL,
    avatar_bg       TEXT NOT NULL DEFAULT '#daeaf8',
    avatar_color    TEXT NOT NULL DEFAULT '#1a5fab',
    notes           TEXT DEFAULT '',
    status          TEXT DEFAULT 'regular',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_clients_name ON clients (name);
CREATE INDEX IF NOT EXISTS idx_clients_phone ON clients (phone);
CREATE INDEX IF NOT EXISTS idx_clients_status ON clients (status);

CREATE TRIGGER trg_clients_updated_at
    BEFORE UPDATE ON clients
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- ═══════════════════════════════════════════════════════════════
--  TABELA: appointments (agendamentos)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS appointments (
    id                SERIAL PRIMARY KEY,
    client_id         INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    service           TEXT NOT NULL,
    appointment_date  DATE NOT NULL,
    appointment_time  TIME NOT NULL,
    status            TEXT NOT NULL DEFAULT 'pending',
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
CREATE INDEX IF NOT EXISTS idx_appointments_client_date ON appointments (client_id, appointment_date);

CREATE TRIGGER trg_appointments_updated_at
    BEFORE UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- ═══════════════════════════════════════════════════════════════
--  TABELA: services (serviços oferecidos)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS services (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    duration    INTEGER NOT NULL DEFAULT 60,
    price       REAL NOT NULL DEFAULT 0,
    color       TEXT DEFAULT '#4a90d9',
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_services_name ON services (name);

-- ═══════════════════════════════════════════════════════════════
--  TABELA: transactions (receitas e despesas)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS transactions (
    id                SERIAL PRIMARY KEY,
    type              TEXT NOT NULL CHECK(type IN ('income', 'expense')),
    description       TEXT NOT NULL,
    amount            REAL NOT NULL,
    category          TEXT DEFAULT '',
    payment_method    TEXT DEFAULT '',
    date              DATE NOT NULL,
    appointment_id    INTEGER REFERENCES appointments(id) ON DELETE SET NULL,
    created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions (date);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions (type);
CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions (category);
CREATE INDEX IF NOT EXISTS idx_transactions_appointment ON transactions (appointment_id);

-- ═══════════════════════════════════════════════════════════════
--  TABELA: settings (configurações chave/valor)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS settings (
    key     TEXT PRIMARY KEY,
    value   TEXT NOT NULL
);

-- ═══════════════════════════════════════════════════════════════
--  TABELA: notifications (notificações do sistema)
-- ═══════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════
--  TABELA: integrations (webhooks, n8n, google calendar)
-- ═══════════════════════════════════════════════════════════════

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

CREATE TRIGGER trg_integrations_updated_at
    BEFORE UPDATE ON integrations
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- ═══════════════════════════════════════════════════════════════
--  TABELA: users (usuários do sistema)
-- ═══════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════
--  VIEW: v_clients — clientes com estatísticas agregadas
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_clients AS
SELECT c.*,
    COALESCE(a.visits, 0) AS visits,
    COALESCE(a.total_spent, 0) AS total_spent,
    a.last_visit
FROM clients c
LEFT JOIN LATERAL (
    SELECT
        COUNT(*) AS visits,
        COALESCE(SUM(price), 0) AS total_spent,
        MAX(appointment_date) AS last_visit
    FROM appointments
    WHERE client_id = c.id AND status != 'cancelled'
) a ON true;

-- ═══════════════════════════════════════════════════════════════
--  VIEW: v_month_stats — estatísticas do mês atual
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_month_stats AS
SELECT
    COALESCE(SUM(CASE WHEN a.status != 'cancelled' THEN a.price ELSE 0 END), 0) AS month_revenue,
    COUNT(*) AS month_appointments,
    COUNT(*) FILTER (WHERE a.status = 'pending') AS month_pending,
    COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'expense'), 0) AS month_expenses,
    COUNT(DISTINCT a.client_id) AS month_clients
FROM appointments a
LEFT JOIN transactions t ON t.date = a.appointment_date
WHERE DATE_TRUNC('month', a.appointment_date) = DATE_TRUNC('month', CURRENT_DATE);

-- ═══════════════════════════════════════════════════════════════
--  VIEW: v_daily_stats — receita/despesa diária do mês
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_daily_stats AS
SELECT
    a.appointment_date AS date,
    COALESCE(SUM(CASE WHEN a.status != 'cancelled' THEN a.price ELSE 0 END), 0) AS revenue,
    COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'expense'), 0) AS expense
FROM appointments a
LEFT JOIN transactions t ON t.date = a.appointment_date
WHERE DATE_TRUNC('month', a.appointment_date) = DATE_TRUNC('month', CURRENT_DATE)
GROUP BY a.appointment_date
ORDER BY a.appointment_date;

