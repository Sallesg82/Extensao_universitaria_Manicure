-- migrate:up
CREATE TABLE integrations (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    type        TEXT NOT NULL CHECK (type IN ('webhook', 'n8n', 'google_calendar')),
    config      JSONB DEFAULT '{}',
    enabled     BOOLEAN DEFAULT TRUE,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_integrations_type ON integrations (type);
CREATE INDEX idx_integrations_enabled ON integrations (enabled);

CREATE TRIGGER trg_integrations_updated_at
    BEFORE UPDATE ON integrations
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- migrate:down
DROP TABLE IF EXISTS integrations CASCADE;
