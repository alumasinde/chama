-- Append-only ledger rows, STK requests and the short-lived idempotency store.

CREATE TABLE transactions (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    group_id BIGINT NOT NULL REFERENCES groups(id) ON DELETE RESTRICT,
    user_id BIGINT NOT NULL REFERENCES users(id),
    transaction_type_id SMALLINT NOT NULL REFERENCES transaction_types(id),
    status_id SMALLINT NOT NULL REFERENCES transaction_statuses(id),
    channel_id SMALLINT REFERENCES payment_channels(id),
    amount NUMERIC(15,2) NOT NULL,
    reference_code TEXT,
    idempotency_key TEXT,
    period_label TEXT,
    narration TEXT NOT NULL,
    raw_callback JSONB,
    recorded_by BIGINT REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    CONSTRAINT transactions_amount_positive CHECK (amount > 0)
);

CREATE UNIQUE INDEX transactions_group_reference_key
    ON transactions (group_id, reference_code) WHERE reference_code IS NOT NULL;
CREATE UNIQUE INDEX transactions_user_idempotency_key
    ON transactions (user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX transactions_group_created_idx ON transactions (group_id, created_at DESC);
CREATE INDEX transactions_user_group_idx ON transactions (user_id, group_id);
CREATE INDEX transactions_group_status_idx ON transactions (group_id, status_id);

CREATE TABLE payment_requests (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    group_id BIGINT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id),
    phone_number TEXT NOT NULL,
    amount NUMERIC(15,2) NOT NULL,
    purpose_type_id SMALLINT NOT NULL REFERENCES transaction_types(id),
    checkout_request_id TEXT NOT NULL UNIQUE,
    merchant_request_id TEXT,
    status_id SMALLINT NOT NULL REFERENCES transaction_statuses(id),
    result_code TEXT,
    result_desc TEXT,
    transaction_id BIGINT REFERENCES transactions(id),
    idempotency_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT payment_requests_amount_positive CHECK (amount > 0)
);

CREATE INDEX payment_requests_group_created_idx ON payment_requests (group_id, created_at DESC);
CREATE INDEX payment_requests_pending_idx ON payment_requests (status_id, created_at)
    WHERE result_code IS NULL;

CREATE TABLE idempotency_keys (
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    route TEXT NOT NULL,
    request_hash BYTEA NOT NULL,
    state TEXT NOT NULL DEFAULT 'in_progress',
    status_code INT,
    response_body JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, key)
);

CREATE INDEX idempotency_keys_expires_idx ON idempotency_keys (expires_at);
