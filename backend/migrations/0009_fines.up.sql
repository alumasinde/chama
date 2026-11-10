-- Fines: group rules and the fines they produce.

CREATE TABLE fine_rules (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    group_id BIGINT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    fine_type_id SMALLINT NOT NULL REFERENCES fine_types(id),
    calculation_method_id SMALLINT NOT NULL REFERENCES fine_calculation_methods(id),
    amount_or_rate NUMERIC(15,2) NOT NULL,
    grace_days SMALLINT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fine_rules_amount_positive CHECK (amount_or_rate > 0),
    CONSTRAINT fine_rules_grace_range CHECK (grace_days BETWEEN 0 AND 60)
);

CREATE UNIQUE INDEX fine_rules_active_type_key ON fine_rules (group_id, fine_type_id)
    WHERE is_active;
CREATE INDEX fine_rules_group_idx ON fine_rules (group_id);

CREATE TABLE fines (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    group_id BIGINT NOT NULL REFERENCES groups(id) ON DELETE RESTRICT,
    user_id BIGINT NOT NULL REFERENCES users(id),
    fine_rule_id BIGINT REFERENCES fine_rules(id),
    fine_type_id SMALLINT NOT NULL REFERENCES fine_types(id),
    amount NUMERIC(15,2) NOT NULL,
    reason TEXT NOT NULL,
    status_id SMALLINT NOT NULL REFERENCES fine_statuses(id),
    period_label TEXT,
    assessed_on DATE NOT NULL DEFAULT CURRENT_DATE,
    waived_by BIGINT REFERENCES users(id),
    waive_reason TEXT,
    payment_transaction_id BIGINT REFERENCES transactions(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fines_amount_positive CHECK (amount > 0),
    CONSTRAINT fines_reason_length CHECK (char_length(reason) BETWEEN 1 AND 200),
    CONSTRAINT fines_waive_fields CHECK (waived_by IS NULL OR waive_reason IS NOT NULL)
);

CREATE UNIQUE INDEX fines_job_key ON fines (group_id, user_id, fine_rule_id, period_label);
CREATE INDEX fines_group_status_idx ON fines (group_id, status_id);
CREATE INDEX fines_user_status_idx ON fines (user_id, status_id);
CREATE INDEX fines_group_created_idx ON fines (group_id, created_at DESC);
