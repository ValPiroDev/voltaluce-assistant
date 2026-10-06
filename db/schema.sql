
BEGIN;

-- 1. Customers
CREATE TABLE customers (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_code  TEXT        NOT NULL UNIQUE,          -- e.g. CL-00001
    first_name     TEXT        NOT NULL,
    last_name      TEXT        NOT NULL,
    email          TEXT,
    phone          TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Supplies (one per customer per type)
CREATE TABLE supplies (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  BIGINT  NOT NULL REFERENCES customers (id) ON DELETE RESTRICT,
    type         TEXT    NOT NULL CHECK (type IN ('electricity', 'gas')),
    meter_code   TEXT    NOT NULL UNIQUE,                -- POD (electricity) / PDR (gas)
    address      TEXT    NOT NULL,
    active       BOOLEAN NOT NULL DEFAULT true,
    CONSTRAINT supplies_customer_type_uq UNIQUE (customer_id, type)
);

-- 3. Bills
CREATE TABLE bills (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supply_id     BIGINT        NOT NULL REFERENCES supplies (id) ON DELETE RESTRICT,
    period_start  DATE          NOT NULL,
    period_end    DATE          NOT NULL,
    amount        NUMERIC(10,2) NOT NULL,
    due_date      DATE          NOT NULL,
    status        TEXT          NOT NULL CHECK (status IN ('paid', 'unpaid', 'overdue')),
    issued_on     DATE          NOT NULL,
    CONSTRAINT bills_period_chk CHECK (period_end > period_start),
    CONSTRAINT bills_amount_chk CHECK (amount >= 0)
);

-- "Latest bill" query: WHERE supply_id = ? ORDER BY issued_on DESC LIMIT 1
CREATE INDEX bills_supply_issued_idx ON bills (supply_id, issued_on DESC);

-- 4. Meter readings
CREATE TABLE meter_readings (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supply_id   BIGINT         NOT NULL REFERENCES supplies (id) ON DELETE RESTRICT,
    value       NUMERIC(12,3)  NOT NULL CHECK (value >= 0),
    read_at     TIMESTAMPTZ    NOT NULL DEFAULT now(),
    source      TEXT           NOT NULL DEFAULT 'voice_agent',
    request_id  TEXT           UNIQUE                    -- idempotency key
);

-- "Last reading" query: WHERE supply_id = ? ORDER BY read_at DESC LIMIT 1
CREATE INDEX meter_readings_supply_read_idx ON meter_readings (supply_id, read_at DESC);

-- 5. Tickets
CREATE TABLE tickets (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  BIGINT      NOT NULL REFERENCES customers (id) ON DELETE RESTRICT,
    description  TEXT        NOT NULL,
    status       TEXT        NOT NULL DEFAULT 'open'
                             CHECK (status IN ('open', 'in_progress', 'closed')),
    priority     TEXT        NOT NULL DEFAULT 'medium'
                             CHECK (priority IN ('low', 'medium', 'high')),
    request_id   TEXT        UNIQUE,                     -- idempotency key
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX tickets_customer_idx ON tickets (customer_id);

-- 6. Calls (one row per ElevenLabs conversation)
CREATE TABLE calls (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    conversation_id  TEXT        NOT NULL UNIQUE,        -- assigned by ElevenLabs
    customer_id      BIGINT      REFERENCES customers (id) ON DELETE SET NULL,  -- nullable: caller may not identify
    duration_sec     INTEGER     CHECK (duration_sec >= 0),
    outcome          TEXT,
    transcript       TEXT,
    metadata         JSONB       NOT NULL DEFAULT '{}'::jsonb,  -- tools called, sentiment, ...
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX calls_customer_idx ON calls (customer_id);

-- 7. Workflow errors (no FKs on purpose: must accept writes even if everything else is broken)
CREATE TABLE workflow_errors (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workflow_name  TEXT,
    execution_id   TEXT,
    node_name      TEXT,
    message        TEXT,
    details        JSONB,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Privileges: tables are owned by the superuser that runs this script.
-- The workflow role gets the minimum it needs and, on purpose, no DELETE:
-- utility data is deactivated, never deleted.
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO voltaluce_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO voltaluce_app;
-- Identity columns are backed by sequences; INSERT needs to read them.
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO voltaluce_app;

COMMIT;
