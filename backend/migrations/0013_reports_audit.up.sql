-- Phase 6: append-only audit trail and generated report files.

CREATE TABLE audit_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    group_id BIGINT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    actor_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    action_code TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id BIGINT,
    entity_public_id UUID,
    before_state JSONB,
    after_state JSONB,
    ip_address TEXT,
    request_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT audit_logs_action_length CHECK (char_length(action_code) BETWEEN 1 AND 80),
    CONSTRAINT audit_logs_entity_length CHECK (char_length(entity_type) BETWEEN 1 AND 80)
);

CREATE INDEX audit_logs_group_created_idx ON audit_logs (group_id, created_at DESC, id DESC);
CREATE INDEX audit_logs_group_action_idx ON audit_logs (group_id, action_code, created_at DESC);
CREATE INDEX audit_logs_actor_idx ON audit_logs (actor_user_id, created_at DESC);

CREATE OR REPLACE FUNCTION reject_audit_log_change() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'audit_logs is append-only';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_logs_append_only
    BEFORE UPDATE OR DELETE ON audit_logs
    FOR EACH ROW EXECUTE FUNCTION reject_audit_log_change();

CREATE TABLE report_jobs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    group_id BIGINT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    requested_by BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    report_code TEXT NOT NULL,
    format TEXT NOT NULL,
    params JSONB NOT NULL DEFAULT '{}'::jsonb,
    status_id SMALLINT NOT NULL REFERENCES report_job_statuses(id),
    file_name TEXT,
    content_type TEXT,
    file_data BYTEA,
    row_count INT NOT NULL DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    CONSTRAINT report_jobs_code_length CHECK (char_length(report_code) BETWEEN 1 AND 60),
    CONSTRAINT report_jobs_format CHECK (format IN ('csv', 'pdf')),
    CONSTRAINT report_jobs_row_count_non_negative CHECK (row_count >= 0)
);

CREATE INDEX report_jobs_group_created_idx ON report_jobs (group_id, created_at DESC, id DESC);
CREATE INDEX report_jobs_group_status_idx ON report_jobs (group_id, status_id);
