-- migrate:up
CREATE TABLE services (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    duration    INTEGER NOT NULL DEFAULT 60,
    buffer      INTEGER NOT NULL DEFAULT 15,
    price       REAL NOT NULL DEFAULT 0,
    color       TEXT DEFAULT '#4a90d9',
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_services_name ON services (name);

-- migrate:down
DROP TABLE IF EXISTS services CASCADE;
