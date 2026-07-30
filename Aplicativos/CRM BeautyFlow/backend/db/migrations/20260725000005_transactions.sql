-- migrate:up
CREATE TABLE transactions (
    id                SERIAL PRIMARY KEY,
    type              TEXT NOT NULL CHECK (type IN ('income', 'expense')),
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

CREATE INDEX idx_transactions_date ON transactions (date);
CREATE INDEX idx_transactions_type ON transactions (type);
CREATE INDEX idx_transactions_category ON transactions (category);
CREATE INDEX idx_transactions_appointment ON transactions (appointment_id);
CREATE INDEX idx_transactions_client ON transactions (client_id);
CREATE INDEX idx_transactions_service ON transactions (service);

-- migrate:down
DROP TABLE IF EXISTS transactions CASCADE;
