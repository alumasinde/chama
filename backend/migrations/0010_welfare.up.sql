-- Welfare: one fund per chama, member contributions and claims with payouts.

CREATE TABLE welfare_funds (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    group_id BIGINT NOT NULL UNIQUE REFERENCES groups(id) ON DELETE CASCADE,
    name TEXT NOT NULL DEFAULT 'Welfare fund',
    monthly_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT welfare_funds_amount_non_negative CHECK (monthly_amount >= 0),
    CONSTRAINT welfare_funds_name_length CHECK (char_length(name) BETWEEN 1 AND 80),
    UNIQUE (id, group_id)
);

CREATE TABLE welfare_contributions (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    group_id BIGINT NOT NULL,
    fund_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    amount NUMERIC(15,2) NOT NULL,
    period_label TEXT NOT NULL,
    transaction_id BIGINT REFERENCES transactions(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT welfare_contributions_amount_positive CHECK (amount > 0),
    CONSTRAINT welfare_contributions_fund_fk FOREIGN KEY (fund_id, group_id)
        REFERENCES welfare_funds (id, group_id) ON DELETE CASCADE,
    CONSTRAINT welfare_contributions_period_length CHECK (char_length(period_label) BETWEEN 1 AND 20),
    UNIQUE (fund_id, user_id, period_label)
);

CREATE INDEX welfare_contributions_group_idx ON welfare_contributions (group_id, created_at DESC);
CREATE INDEX welfare_contributions_user_idx ON welfare_contributions (user_id, group_id);

CREATE TABLE welfare_claims (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    group_id BIGINT NOT NULL,
    fund_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    amount NUMERIC(15,2) NOT NULL,
    reason TEXT NOT NULL,
    status_id SMALLINT NOT NULL REFERENCES welfare_claim_statuses(id),
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_by BIGINT REFERENCES users(id),
    decided_at TIMESTAMPTZ,
    payout_transaction_id BIGINT REFERENCES transactions(id) ON DELETE RESTRICT,
    comment TEXT,
    CONSTRAINT welfare_claims_amount_positive CHECK (amount > 0),
    CONSTRAINT welfare_claims_reason_length CHECK (char_length(reason) BETWEEN 1 AND 300),
    CONSTRAINT welfare_claims_fund_fk FOREIGN KEY (fund_id, group_id)
        REFERENCES welfare_funds (id, group_id) ON DELETE CASCADE,
    UNIQUE (id, group_id)
);

CREATE INDEX welfare_claims_group_status_idx ON welfare_claims (group_id, status_id);
CREATE INDEX welfare_claims_user_idx ON welfare_claims (user_id, group_id);
