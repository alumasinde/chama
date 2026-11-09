-- Chamas and their membership rows. Role and status always come from lookups.

CREATE TABLE groups (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    invite_code TEXT NOT NULL UNIQUE,
    description TEXT,
    currency_code CHAR(3) NOT NULL DEFAULT 'KES',
    contribution_amount NUMERIC(15,2) NOT NULL,
    contribution_frequency_id SMALLINT NOT NULL REFERENCES contribution_frequencies(id),
    contribution_day SMALLINT NOT NULL DEFAULT 1,
    late_grace_days INT NOT NULL DEFAULT 3,
    created_by BIGINT NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT groups_contribution_amount_positive CHECK (contribution_amount > 0),
    CONSTRAINT groups_contribution_day_range CHECK (contribution_day BETWEEN 0 AND 28),
    CONSTRAINT groups_late_grace_non_negative CHECK (late_grace_days >= 0)
);

CREATE INDEX groups_created_by_idx ON groups (created_by);

CREATE TABLE group_members (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    group_id BIGINT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id SMALLINT NOT NULL REFERENCES member_roles(id),
    status_id SMALLINT NOT NULL REFERENCES member_statuses(id),
    joined_at TIMESTAMPTZ,
    approved_by BIGINT REFERENCES users(id),
    exited_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (group_id, user_id)
);

CREATE INDEX group_members_user_idx ON group_members (user_id, group_id);
CREATE INDEX group_members_group_status_idx ON group_members (group_id, status_id);
