-- name: CreateTransaction :one
WITH created AS (
    INSERT INTO transactions (
        group_id, user_id, transaction_type_id, status_id, channel_id,
        amount, idempotency_key, narration
    ) VALUES (
        sqlc.arg(group_id),
        sqlc.arg(user_id),
        (SELECT t.id FROM transaction_types t WHERE t.code = sqlc.arg(transaction_type)),
        (SELECT s.id FROM transaction_statuses s WHERE s.code = 'pending'),
        (SELECT c.id FROM payment_channels c WHERE c.code = sqlc.arg(channel)),
        (sqlc.arg(amount_cents)::bigint / 100.0)::numeric(15,2),
        sqlc.narg(idempotency_key),
        sqlc.arg(narration)
    )
    RETURNING *
)
SELECT c.id, c.public_id, c.user_id, c.reference_code, c.narration, c.created_at, c.completed_at,
       tt.code AS transaction_type, ts.code AS status, ch.code AS channel,
       (round(c.amount * 100))::bigint AS amount_cents
FROM created c
JOIN transaction_types tt ON tt.id = c.transaction_type_id
JOIN transaction_statuses ts ON ts.id = c.status_id
LEFT JOIN payment_channels ch ON ch.id = c.channel_id;

-- name: SettleTransaction :one
WITH settled AS (
    UPDATE transactions
    SET status_id = (SELECT s.id FROM transaction_statuses s WHERE s.code = sqlc.arg(status)),
        reference_code = sqlc.narg(reference_code),
        raw_callback = sqlc.narg(raw_callback),
        completed_at = now()
    WHERE transactions.id = sqlc.arg(id)
      AND transactions.status_id = (SELECT s.id FROM transaction_statuses s WHERE s.code = 'pending')
    RETURNING *
)
SELECT c.id, c.public_id, c.user_id, c.reference_code, c.narration, c.created_at, c.completed_at,
       tt.code AS transaction_type, ts.code AS status, ch.code AS channel,
       (round(c.amount * 100))::bigint AS amount_cents
FROM settled c
JOIN transaction_types tt ON tt.id = c.transaction_type_id
JOIN transaction_statuses ts ON ts.id = c.status_id
LEFT JOIN payment_channels ch ON ch.id = c.channel_id;

-- name: GetTransaction :one
SELECT t.id, t.public_id, t.user_id, u.public_id AS user_public_id, u.first_name, u.last_name,
       tt.code AS transaction_type, ts.code AS status, ch.code AS channel,
       (round(t.amount * 100))::bigint AS amount_cents,
       t.reference_code, t.narration, t.period_label, t.created_at, t.completed_at
FROM transactions t
JOIN users u ON u.id = t.user_id
JOIN transaction_types tt ON tt.id = t.transaction_type_id
JOIN transaction_statuses ts ON ts.id = t.status_id
LEFT JOIN payment_channels ch ON ch.id = t.channel_id
WHERE t.group_id = sqlc.arg(group_id) AND t.public_id = sqlc.arg(public_id);

-- name: ListTransactions :many
SELECT t.id, t.public_id, t.user_id, u.public_id AS user_public_id, u.first_name, u.last_name,
       tt.code AS transaction_type, ts.code AS status, ch.code AS channel,
       (round(t.amount * 100))::bigint AS amount_cents,
       t.reference_code, t.narration, t.period_label, t.created_at, t.completed_at
FROM transactions t
JOIN users u ON u.id = t.user_id
JOIN transaction_types tt ON tt.id = t.transaction_type_id
JOIN transaction_statuses ts ON ts.id = t.status_id
LEFT JOIN payment_channels ch ON ch.id = t.channel_id
WHERE t.group_id = sqlc.arg(group_id)
  AND (sqlc.narg(before_at)::timestamptz IS NULL
       OR (t.created_at, t.id) < (sqlc.narg(before_at)::timestamptz, sqlc.narg(before_id)::bigint))
ORDER BY t.created_at DESC, t.id DESC
LIMIT sqlc.arg(row_limit);

-- name: CreatePaymentRequest :one
INSERT INTO payment_requests (
    group_id, user_id, phone_number, amount, purpose_type_id,
    checkout_request_id, merchant_request_id, status_id, transaction_id, idempotency_key
) VALUES (
    sqlc.arg(group_id),
    sqlc.arg(user_id),
    sqlc.arg(phone_number),
    (sqlc.arg(amount_cents)::bigint / 100.0)::numeric(15,2),
    (SELECT t.id FROM transaction_types t WHERE t.code = sqlc.arg(purpose)),
    sqlc.arg(checkout_request_id),
    sqlc.narg(merchant_request_id),
    (SELECT s.id FROM transaction_statuses s WHERE s.code = 'pending'),
    sqlc.narg(transaction_id),
    sqlc.narg(idempotency_key)
)
RETURNING id, public_id, checkout_request_id;

-- name: GetPaymentRequestByCheckout :one
SELECT id, public_id, group_id, user_id, phone_number, transaction_id,
       (round(amount * 100))::bigint AS amount_cents
FROM payment_requests
WHERE group_id = sqlc.arg(group_id) AND checkout_request_id = sqlc.arg(checkout_request_id);

-- name: SettlePaymentRequest :exec
UPDATE payment_requests p
SET status_id = (SELECT s.id FROM transaction_statuses s WHERE s.code = sqlc.arg(status)),
    result_code = sqlc.narg(result_code),
    result_desc = sqlc.narg(result_desc),
    transaction_id = COALESCE(sqlc.narg(transaction_id), p.transaction_id),
    updated_at = now()
WHERE p.id = sqlc.arg(id);

-- name: BeginIdempotency :execrows
INSERT INTO idempotency_keys (user_id, key, route, request_hash, state, expires_at)
VALUES (sqlc.arg(user_id), sqlc.arg(key), sqlc.arg(route), sqlc.arg(request_hash),
        'in_progress', now() + interval '24 hours')
ON CONFLICT (user_id, key) DO NOTHING;

-- name: GetIdempotency :one
SELECT user_id, key, route, request_hash, state, status_code, response_body, expires_at
FROM idempotency_keys
WHERE user_id = sqlc.arg(user_id) AND key = sqlc.arg(key);

-- name: CompleteIdempotency :exec
UPDATE idempotency_keys
SET state = 'completed', status_code = sqlc.arg(status_code), response_body = sqlc.arg(response_body)
WHERE user_id = sqlc.arg(user_id) AND key = sqlc.arg(key);

-- name: DeleteIdempotency :exec
DELETE FROM idempotency_keys WHERE user_id = sqlc.arg(user_id) AND key = sqlc.arg(key);

-- name: RecordManualContribution :one
-- The join on an active membership means a non-member or exited member writes no row.
INSERT INTO transactions (
    group_id, user_id, transaction_type_id, status_id, channel_id,
    amount, reference_code, narration, recorded_by, completed_at
)
SELECT
    sqlc.arg(group_id),
    gm.user_id,
    (SELECT t.id FROM transaction_types t WHERE t.code = 'contribution'),
    (SELECT s.id FROM transaction_statuses s WHERE s.code = 'completed'),
    (SELECT c.id FROM payment_channels c WHERE c.code = sqlc.arg(channel)),
    (sqlc.arg(amount_cents)::bigint / 100.0)::numeric(15,2),
    sqlc.arg(reference_code),
    sqlc.arg(narration),
    sqlc.arg(recorded_by),
    now()
FROM group_members gm
JOIN member_statuses ms ON ms.id = gm.status_id
WHERE gm.group_id = sqlc.arg(group_id)
  AND gm.user_id = (SELECT u.id FROM users u WHERE u.public_id = sqlc.arg(member_public_id))
  AND ms.code = 'active'
RETURNING id, public_id, user_id, reference_code, narration, created_at, completed_at;
