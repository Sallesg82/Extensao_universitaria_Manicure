-- migrate:up
CREATE TABLE settings (
    key     TEXT PRIMARY KEY,
    value   TEXT NOT NULL
);

-- migrate:down
DROP TABLE IF EXISTS settings CASCADE;
