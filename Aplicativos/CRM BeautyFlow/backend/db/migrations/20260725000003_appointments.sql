-- migrate:up
CREATE TABLE appointments (
    id                SERIAL PRIMARY KEY,
    client_id         INTEGER REFERENCES clients(id) ON DELETE SET NULL,
    service           TEXT NOT NULL,
    appointment_date  DATE NOT NULL,
    appointment_time  TIME NOT NULL,
    status            TEXT NOT NULL DEFAULT 'pending',
    payment_status    TEXT NOT NULL DEFAULT 'unpaid' CHECK (payment_status IN ('paid', 'unpaid')),
    price             REAL NOT NULL DEFAULT 0,
    duration          INTEGER DEFAULT 60,
    notes             TEXT DEFAULT '',
    google_event_id   TEXT DEFAULT '',
    google_html_link  TEXT DEFAULT '',
    created_at        TIMESTAMPTZ DEFAULT NOW(),
    updated_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_appointments_client ON appointments (client_id);
CREATE INDEX idx_appointments_date ON appointments (appointment_date);
CREATE INDEX idx_appointments_status ON appointments (status);
CREATE INDEX idx_appointments_payment_status ON appointments (payment_status);
CREATE INDEX idx_appointments_client_date ON appointments (client_id, appointment_date);

CREATE TRIGGER trg_appointments_updated_at
    BEFORE UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- migrate:down
DROP TABLE IF EXISTS appointments CASCADE;
