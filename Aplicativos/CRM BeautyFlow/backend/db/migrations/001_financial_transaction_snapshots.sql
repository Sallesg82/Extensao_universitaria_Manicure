-- Separa receita financeira (lançamentos) de dados de clientes.
-- Execute no SQL Editor do Supabase (uma vez).


ALTER TABLE transactions
    ADD COLUMN IF NOT EXISTS client_id INTEGER REFERENCES clients(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS client_name TEXT DEFAULT '',
    ADD COLUMN IF NOT EXISTS service TEXT DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_transactions_client ON transactions (client_id);
CREATE INDEX IF NOT EXISTS idx_transactions_service ON transactions (service);