CREATE TABLE IF NOT EXISTS business_hours (
    id          SERIAL PRIMARY KEY,
    day         TEXT NOT NULL UNIQUE,
    open        TEXT NOT NULL DEFAULT '08:00',
    close       TEXT NOT NULL DEFAULT '18:00',
    closed      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TRIGGER IF NOT EXISTS trg_business_hours_updated_at
    BEFORE UPDATE ON business_hours
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- Adicionar coluna buffer se não existir (margem extra entre agendamentos)
ALTER TABLE services ADD COLUMN IF NOT EXISTS buffer INTEGER NOT NULL DEFAULT 15;
