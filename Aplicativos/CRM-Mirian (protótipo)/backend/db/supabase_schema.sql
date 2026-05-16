-- BeautyFlow - Schema Supabase
-- 1. Crie as tabelas e views
-- 2. Depois insira os seeds
--
-- https://supabase.com/dashboard/project/omtqedkinvyslsucryze/sql/new

-- ══════════════════════════════════════════
--  TABELAS
-- ══════════════════════════════════════════

CREATE TABLE IF NOT EXISTS clients (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    phone TEXT NOT NULL,
    email TEXT DEFAULT '',
    avatar_initials TEXT NOT NULL,
    avatar_bg TEXT NOT NULL DEFAULT '#daeaf8',
    avatar_color TEXT NOT NULL DEFAULT '#1a5fab',
    notes TEXT DEFAULT '',
    status TEXT DEFAULT 'regular',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS appointments (
    id SERIAL PRIMARY KEY,
    client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    service TEXT NOT NULL,
    appointment_date DATE NOT NULL,
    appointment_time TIME NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    price REAL NOT NULL DEFAULT 0,
    duration INTEGER DEFAULT 60,
    notes TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS services (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    duration INTEGER NOT NULL DEFAULT 60,
    price REAL NOT NULL DEFAULT 0,
    color TEXT DEFAULT '#4a90d9',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    type TEXT NOT NULL CHECK(type IN ('income','expense')),
    description TEXT NOT NULL,
    amount REAL NOT NULL,
    category TEXT DEFAULT '',
    payment_method TEXT DEFAULT '',
    date DATE NOT NULL,
    appointment_id INTEGER REFERENCES appointments(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    phone TEXT DEFAULT '',
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'admin',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ══════════════════════════════════════════
--  VIEWS
-- ══════════════════════════════════════════

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
    WHERE client_id = c.id
) a ON true;

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

-- ══════════════════════════════════════════
--  SEED DATA
-- ══════════════════════════════════════════

INSERT INTO clients (name, phone, email, avatar_initials, avatar_bg, avatar_color, status, created_at) VALUES
    ('Ana Paula Silva', '(11) 98765-4321', 'ana@email.com', 'AP', '#daeaf8', '#1a5fab', 'frequente', '2024-01-15'),
    ('Carla Mendes', '(11) 97654-3210', 'carla@email.com', 'CM', '#f0e8f8', '#6a2e8a', 'regular', '2024-03-10'),
    ('Fernanda Costa', '(11) 96543-2109', 'fernanda@email.com', 'FC', '#e8f8ee', '#2e8a5a', 'regular', '2024-05-20'),
    ('Juliana Rocha', '(11) 95432-1098', 'juliana@email.com', 'JR', '#fdf3dc', '#8c5e10', 'regular', '2024-06-05'),
    ('Mariana Torres', '(11) 94321-0987', 'mariana@email.com', 'MT', '#fce8e8', '#8a2e2e', 'novo', '2025-02-01'),
    ('Patricia Lima', '(11) 93210-9876', 'patricia@email.com', 'PL', '#e8f0fc', '#2e5e8a', 'novo', '2026-04-01'),
    ('Rafaela Nunes', '(11) 92109-8765', 'rafaela@email.com', 'RN', '#f0f8e8', '#4a8a2e', 'frequente', '2023-11-10'),
    ('Beatriz Neves', '(11) 91098-7654', 'beatriz@email.com', 'BN', '#f8e8f4', '#8a2e6e', 'frequente', '2023-12-05'),
    ('Lúcia Ferreira', '(11) 90987-6543', 'lucia@email.com', 'LF', '#e8fcf8', '#2e8a7a', 'novo', '2026-04-15')
ON CONFLICT DO NOTHING;

INSERT INTO services (name, duration, price, color) VALUES
    ('Manicure Simples', 40, 35, '#4a90d9'),
    ('Pedicure Simples', 50, 40, '#2563a8'),
    ('Manicure + Pedicure', 80, 70, '#4a90d9'),
    ('Unhas em Gel', 90, 90, '#3a7abf'),
    ('Alongamento de Unhas', 120, 120, '#1a5fab'),
    ('Blindagem de Unhas', 60, 65, '#0f2340'),
    ('Design de Sobrancelha', 30, 45, '#8aaccb'),
    ('Sobrancelha + Manicure', 70, 80, '#4e8f6a')
ON CONFLICT (name) DO NOTHING;
