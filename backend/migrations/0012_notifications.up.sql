-- In-app notifications plus the dedupe key that makes each event create exactly one row.

CREATE TABLE notifications (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    group_id BIGINT REFERENCES groups(id) ON DELETE CASCADE,
    type_id SMALLINT NOT NULL REFERENCES notification_types(id),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    dedupe_key TEXT,
    read_at TIMESTAMPTZ,
    pushed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT notifications_title_length CHECK (char_length(title) BETWEEN 1 AND 120),
    CONSTRAINT notifications_body_length CHECK (char_length(body) BETWEEN 1 AND 500),
    UNIQUE (user_id, dedupe_key)
);

CREATE INDEX notifications_user_created_idx ON notifications (user_id, created_at DESC);
CREATE INDEX notifications_user_unread_idx ON notifications (user_id, created_at DESC)
    WHERE read_at IS NULL;
