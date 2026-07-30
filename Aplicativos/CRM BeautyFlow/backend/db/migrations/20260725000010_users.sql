-- migrate:up
CREATE TABLE users (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    email           TEXT NOT NULL UNIQUE,
    phone           TEXT DEFAULT '',
    password_hash   TEXT NOT NULL,
    role            TEXT NOT NULL DEFAULT 'admin',
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users (email);

-- migrate:down
DROP TABLE IF EXISTS users CASCADE;
