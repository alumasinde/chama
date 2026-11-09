-- Database-level guarantee: a settled ledger row can never be edited or deleted.

CREATE OR REPLACE FUNCTION transactions_append_only() RETURNS trigger AS $$
DECLARE
    old_status TEXT;
    new_status TEXT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'transactions are append-only';
    END IF;

    SELECT code INTO old_status FROM transaction_statuses WHERE id = OLD.status_id;
    IF old_status <> 'pending' THEN
        RAISE EXCEPTION 'transaction % is already settled', OLD.id;
    END IF;

    SELECT code INTO new_status FROM transaction_statuses WHERE id = NEW.status_id;
    IF new_status NOT IN ('completed', 'failed', 'cancelled') THEN
        RAISE EXCEPTION 'invalid transaction transition % -> %', old_status, new_status;
    END IF;

    IF NEW.group_id <> OLD.group_id
       OR NEW.user_id <> OLD.user_id
       OR NEW.amount <> OLD.amount
       OR NEW.transaction_type_id <> OLD.transaction_type_id
       OR NEW.channel_id IS DISTINCT FROM OLD.channel_id
       OR NEW.created_at <> OLD.created_at THEN
        RAISE EXCEPTION 'only status, reference, callback and completion may change';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_transactions_append_only
    BEFORE UPDATE OR DELETE ON transactions
    FOR EACH ROW EXECUTE FUNCTION transactions_append_only();
