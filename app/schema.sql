-- Initial schema, applied with `flask --app app init-db`.
-- Future schema changes need explicit migrations; IF NOT EXISTS is not a migration engine.
CREATE TABLE IF NOT EXISTS helpdesk.tickets (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seed_key TEXT UNIQUE,
    title VARCHAR(120) NOT NULL CHECK (length(btrim(title)) > 0),
    description VARCHAR(2000) NOT NULL DEFAULT '',
    requester VARCHAR(80) NOT NULL CHECK (length(btrim(requester)) > 0),
    status VARCHAR(10) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS tickets_created_idx ON helpdesk.tickets(created_at DESC, id DESC);
