-- Rotation cycles, slots, proposals, proposed orders and one changeable vote per member.

CREATE TABLE rotation_cycles (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    group_id BIGINT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    status_id SMALLINT NOT NULL REFERENCES rotation_cycle_statuses(id),
    ordering_mode_id SMALLINT NOT NULL REFERENCES rotation_ordering_modes(id),
    contribution_amount NUMERIC(15,2) NOT NULL,
    starts_on DATE NOT NULL,
    member_count SMALLINT NOT NULL,
    draw_seed TEXT,
    created_by BIGINT NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    CONSTRAINT rotation_cycles_amount_positive CHECK (contribution_amount > 0),
    CONSTRAINT rotation_cycles_member_count_positive CHECK (member_count > 0),
    CONSTRAINT rotation_cycles_name_length CHECK (char_length(name) BETWEEN 1 AND 80),
    UNIQUE (id, group_id)
);

CREATE INDEX rotation_cycles_group_status_idx ON rotation_cycles (group_id, status_id);

CREATE TABLE rotation_slots (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    group_id BIGINT NOT NULL,
    cycle_id BIGINT NOT NULL,
    member_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    position SMALLINT NOT NULL,
    payout_date DATE NOT NULL,
    payout_transaction_id BIGINT REFERENCES transactions(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT rotation_slots_position_positive CHECK (position > 0),
    CONSTRAINT rotation_slots_cycle_fk FOREIGN KEY (cycle_id, group_id)
        REFERENCES rotation_cycles (id, group_id) ON DELETE CASCADE,
    UNIQUE (cycle_id, position),
    UNIQUE (cycle_id, member_id)
);

CREATE INDEX rotation_slots_group_idx ON rotation_slots (group_id, cycle_id);
CREATE INDEX rotation_slots_member_idx ON rotation_slots (member_id, group_id);

CREATE TABLE rotation_proposals (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    group_id BIGINT NOT NULL,
    cycle_id BIGINT NOT NULL,
    proposed_by BIGINT NOT NULL REFERENCES users(id),
    status_id SMALLINT NOT NULL REFERENCES rotation_proposal_statuses(id),
    quorum_percent SMALLINT NOT NULL DEFAULT 60,
    eligible_members SMALLINT NOT NULL,
    opens_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    closes_at TIMESTAMPTZ NOT NULL,
    closed_at TIMESTAMPTZ,
    result JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT rotation_proposals_quorum_range CHECK (quorum_percent BETWEEN 1 AND 100),
    CONSTRAINT rotation_proposals_eligible_positive CHECK (eligible_members > 0),
    CONSTRAINT rotation_proposals_window CHECK (closes_at > opens_at),
    CONSTRAINT rotation_proposals_cycle_fk FOREIGN KEY (cycle_id, group_id)
        REFERENCES rotation_cycles (id, group_id) ON DELETE CASCADE,
    UNIQUE (id, group_id)
);

CREATE INDEX rotation_proposals_group_idx ON rotation_proposals (group_id, created_at DESC);
CREATE UNIQUE INDEX rotation_proposals_one_open_idx ON rotation_proposals (cycle_id)
    WHERE closed_at IS NULL;

CREATE TABLE rotation_proposal_slots (
    proposal_id BIGINT NOT NULL,
    group_id BIGINT NOT NULL,
    position SMALLINT NOT NULL,
    member_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT rotation_proposal_slots_pkey PRIMARY KEY (proposal_id, position),
    CONSTRAINT rotation_proposal_slots_position_positive CHECK (position > 0),
    CONSTRAINT rotation_proposal_slots_proposal_fk FOREIGN KEY (proposal_id, group_id)
        REFERENCES rotation_proposals (id, group_id) ON DELETE CASCADE,
    UNIQUE (proposal_id, member_id)
);

CREATE TABLE rotation_votes (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    group_id BIGINT NOT NULL,
    proposal_id BIGINT NOT NULL,
    member_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    choice_id SMALLINT NOT NULL REFERENCES vote_choices(id),
    cast_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT rotation_votes_proposal_fk FOREIGN KEY (proposal_id, group_id)
        REFERENCES rotation_proposals (id, group_id) ON DELETE CASCADE,
    UNIQUE (proposal_id, member_id)
);

CREATE INDEX rotation_votes_group_idx ON rotation_votes (group_id, proposal_id);
