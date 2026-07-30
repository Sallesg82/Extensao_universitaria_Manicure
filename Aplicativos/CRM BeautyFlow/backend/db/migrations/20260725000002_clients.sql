-- migrate:up
CREATE TABLE clients (
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

CREATE INDEX idx_clients_name ON clients (name);
CREATE INDEX idx_clients_phone ON clients (phone);
CREATE INDEX idx_clients_status ON clients (status);

CREATE TRIGGER trg_clients_updated_at
    BEFORE UPDATE ON clients
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- migrate:down
DROP TABLE IF EXISTS clients CASCADE;
