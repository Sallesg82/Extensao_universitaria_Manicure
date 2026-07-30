-- migrate:up
CREATE TABLE notifications (
    id              SERIAL PRIMARY KEY,
    type            TEXT NOT NULL,
    title           TEXT NOT NULL,
    message         TEXT NOT NULL,
    related_id      INTEGER DEFAULT NULL,
    related_type    TEXT DEFAULT '',
    read            BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_notifications_read ON notifications (read);
CREATE INDEX idx_notifications_created ON notifications (created_at DESC);

-- migrate:down
DROP TABLE IF EXISTS notifications CASCADE;
