DROP TABLE IF EXISTS report_jobs;
DROP TRIGGER IF EXISTS audit_logs_append_only ON audit_logs;
DROP FUNCTION IF EXISTS reject_audit_log_change();
DROP TABLE IF EXISTS audit_logs;
