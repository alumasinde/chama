-- Loans: settings, applications, guarantors, approvals and the persisted schedule.

CREATE TABLE group_loan_settings (
    group_id BIGINT PRIMARY KEY REFERENCES groups(id) ON DELETE CASCADE,
    interest_rate NUMERIC(6,3) NOT NULL DEFAULT 10.000,
    interest_method_id SMALLINT NOT NULL REFERENCES interest_methods(id),
    max_multiple_of_savings NUMERIC(6,2) NOT NULL DEFAULT 3.00,
    max_term_months SMALLINT NOT NULL DEFAULT 12,
    guarantors_required SMALLINT NOT NULL DEFAULT 1,
    allow_loans BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT group_loan_settings_rate_non_negative CHECK (interest_rate >= 0),
    CONSTRAINT group_loan_settings_multiple_positive CHECK (max_multiple_of_savings > 0),
    CONSTRAINT group_loan_settings_term_range CHECK (max_term_months BETWEEN 1 AND 60),
    CONSTRAINT group_loan_settings_guarantors_range CHECK (guarantors_required BETWEEN 0 AND 10)
);

CREATE TABLE loans (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    group_id BIGINT NOT NULL REFERENCES groups(id) ON DELETE RESTRICT,
    user_id BIGINT NOT NULL REFERENCES users(id),
    principal NUMERIC(15,2) NOT NULL,
    interest_rate NUMERIC(6,3) NOT NULL,
    interest_method_id SMALLINT NOT NULL REFERENCES interest_methods(id),
    term_months SMALLINT NOT NULL,
    status_id SMALLINT NOT NULL REFERENCES loan_statuses(id),
    total_interest NUMERIC(15,2) NOT NULL DEFAULT 0,
    total_payable NUMERIC(15,2) NOT NULL DEFAULT 0,
    purpose TEXT NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    approved_at TIMESTAMPTZ,
    disbursed_at TIMESTAMPTZ,
    disbursement_transaction_id BIGINT REFERENCES transactions(id),
    created_by BIGINT NOT NULL REFERENCES users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT loans_principal_positive CHECK (principal > 0),
    CONSTRAINT loans_term_range CHECK (term_months BETWEEN 1 AND 60),
    CONSTRAINT loans_rate_non_negative CHECK (interest_rate >= 0),
    CONSTRAINT loans_purpose_length CHECK (char_length(purpose) BETWEEN 1 AND 200),
    UNIQUE (id, group_id)
);

CREATE INDEX loans_group_status_idx ON loans (group_id, status_id);
CREATE INDEX loans_user_group_idx ON loans (user_id, group_id);
CREATE INDEX loans_group_requested_idx ON loans (group_id, requested_at DESC);

CREATE TABLE loan_guarantors (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    group_id BIGINT NOT NULL,
    loan_id BIGINT NOT NULL,
    guarantor_user_id BIGINT NOT NULL REFERENCES users(id),
    amount_guaranteed NUMERIC(15,2) NOT NULL,
    status_id SMALLINT NOT NULL REFERENCES guarantor_statuses(id),
    responded_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT loan_guarantors_amount_positive CHECK (amount_guaranteed > 0),
    CONSTRAINT loan_guarantors_loan_fk FOREIGN KEY (loan_id, group_id)
        REFERENCES loans (id, group_id) ON DELETE CASCADE,
    UNIQUE (loan_id, guarantor_user_id)
);

CREATE INDEX loan_guarantors_user_status_idx ON loan_guarantors (guarantor_user_id, status_id);
CREATE INDEX loan_guarantors_group_idx ON loan_guarantors (group_id);

CREATE TABLE loan_schedule_items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    group_id BIGINT NOT NULL,
    loan_id BIGINT NOT NULL,
    installment_no SMALLINT NOT NULL,
    due_date DATE NOT NULL,
    principal_due NUMERIC(15,2) NOT NULL,
    interest_due NUMERIC(15,2) NOT NULL,
    paid_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    paid_at TIMESTAMPTZ,
    CONSTRAINT loan_schedule_due_positive CHECK (principal_due > 0),
    CONSTRAINT loan_schedule_interest_non_negative CHECK (interest_due >= 0),
    CONSTRAINT loan_schedule_paid_non_negative CHECK (paid_amount >= 0),
    CONSTRAINT loan_schedule_loan_fk FOREIGN KEY (loan_id, group_id)
        REFERENCES loans (id, group_id) ON DELETE CASCADE,
    UNIQUE (loan_id, installment_no)
);

CREATE INDEX loan_schedule_due_idx ON loan_schedule_items (due_date, loan_id) WHERE paid_at IS NULL;
CREATE INDEX loan_schedule_group_idx ON loan_schedule_items (group_id, loan_id);

CREATE TABLE loan_approvals (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    group_id BIGINT NOT NULL,
    loan_id BIGINT NOT NULL,
    approver_id BIGINT NOT NULL REFERENCES users(id),
    decision_id SMALLINT NOT NULL REFERENCES approval_decisions(id),
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT loan_approvals_loan_fk FOREIGN KEY (loan_id, group_id)
        REFERENCES loans (id, group_id) ON DELETE CASCADE,
    UNIQUE (loan_id, approver_id)
);

CREATE INDEX loan_approvals_group_idx ON loan_approvals (group_id, loan_id);
