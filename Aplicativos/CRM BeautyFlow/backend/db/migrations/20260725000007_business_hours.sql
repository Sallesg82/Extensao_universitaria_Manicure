-- migrate:up
CREATE TABLE business_hours (
    id          SERIAL PRIMARY KEY,
    day         TEXT NOT NULL UNIQUE,
    open        TEXT NOT NULL DEFAULT '08:00',
    close       TEXT NOT NULL DEFAULT '18:00',
    closed      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TRIGGER trg_business_hours_updated_at
    BEFORE UPDATE ON business_hours
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

INSERT INTO business_hours (day, open, close, closed) VALUES
    ('segunda', '08:00', '18:00', false),
    ('terca',   '08:00', '18:00', false),
    ('quarta',  '08:00', '18:00', false),
    ('quinta',  '08:00', '18:00', false),
    ('sexta',   '08:00', '18:00', false),
    ('sabado',  '08:00', '13:00', false),
    ('domingo', '',      '',      true)
ON CONFLICT (day) DO NOTHING;

-- migrate:down
DROP TABLE IF EXISTS business_hours CASCADE;
