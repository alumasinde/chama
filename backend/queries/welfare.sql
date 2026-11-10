-- Welfare fund, contributions, claims and claim payouts.

-- name: GetWelfareFund :one
SELECT wf.id, wf.name,
       (round(wf.monthly_amount * 100))::bigint AS monthly_cents,
       wf.is_active, wf.created_at, wf.updated_at,
       COALESCE((
           SELECT round(sum(wc.amount) * 100)::bigint
           FROM welfare_contributions wc WHERE wc.fund_id = wf.id
       ), 0)::bigint AS contributed_cents,
       COALESCE((
           SELECT round(sum(t.amount) * 100)::bigint
           FROM transactions t
           JOIN transaction_types tt ON tt.id = t.transaction_type_id
           JOIN transaction_statuses ts ON ts.id = t.status_id
           WHERE t.group_id = wf.group_id AND tt.code = 'welfare_payout' AND ts.code = 'completed'
       ), 0)::bigint AS paid_out_cents
FROM welfare_funds wf
WHERE wf.group_id = sqlc.arg(group_id);

-- name: UpsertWelfareFund :one
INSERT INTO welfare_funds (group_id, name, monthly_amount, is_active)
VALUES (
    sqlc.arg(group_id), sqlc.arg(name),
    (sqlc.arg(monthly_cents)::bigint / 100.0)::numeric(15,2),
    sqlc.arg(is_active)
)
ON CONFLICT (group_id) DO UPDATE
SET name = EXCLUDED.name, monthly_amount = EXCLUDED.monthly_amount,
    is_active = EXCLUDED.is_active, updated_at = now()
RETURNING id;

-- name: InsertWelfareContribution :one
INSERT INTO welfare_contributions (
    group_id, fund_id, user_id, amount, period_label, transaction_id
) VALUES (
    sqlc.arg(group_id), sqlc.arg(fund_id), sqlc.arg(user_id),
    (sqlc.arg(amount_cents)::bigint / 100.0)::numeric(15,2),
    sqlc.arg(period_label), sqlc.narg(transaction_id)
)
ON CONFLICT (fund_id, user_id, period_label) DO NOTHING
RETURNING public_id, created_at;

-- name: ListWelfareContributions :many
SELECT wc.public_id, u.public_id AS user_public_id, u.first_name, u.last_name,
       (round(wc.amount * 100))::bigint AS amount_cents,
       wc.period_label, t.public_id AS transaction_public_id, wc.created_at
FROM welfare_contributions wc
JOIN users u ON u.id = wc.user_id
LEFT JOIN transactions t ON t.id = wc.transaction_id
WHERE wc.group_id = sqlc.arg(group_id)
  AND (sqlc.narg(user_id)::bigint IS NULL OR wc.user_id = sqlc.narg(user_id))
ORDER BY wc.created_at DESC, wc.id DESC
LIMIT sqlc.arg(row_limit);

-- name: InsertWelfareClaim :one
INSERT INTO welfare_claims (group_id, fund_id, user_id, amount, reason, status_id)
VALUES (
    sqlc.arg(group_id), sqlc.arg(fund_id), sqlc.arg(user_id),
    (sqlc.arg(amount_cents)::bigint / 100.0)::numeric(15,2),
    sqlc.arg(reason),
    (SELECT wcs.id FROM welfare_claim_statuses wcs WHERE wcs.code = 'pending')
)
RETURNING id, public_id, requested_at;

-- name: GetWelfareClaim :one
SELECT wc.id, wc.public_id, wc.user_id, u.public_id AS user_public_id, u.first_name, u.last_name,
       (round(wc.amount * 100))::bigint AS amount_cents,
       wc.reason, wcs.code AS status, wc.requested_at, wc.decided_at, wc.comment,
       du.first_name AS decided_by_first_name, du.last_name AS decided_by_last_name,
       pt.public_id AS payout_transaction_public_id
FROM welfare_claims wc
JOIN users u ON u.id = wc.user_id
JOIN welfare_claim_statuses wcs ON wcs.id = wc.status_id
LEFT JOIN users du ON du.id = wc.decided_by
LEFT JOIN transactions pt ON pt.id = wc.payout_transaction_id
WHERE wc.group_id = sqlc.arg(group_id) AND wc.public_id = sqlc.arg(public_id);

-- name: ListWelfareClaims :many
SELECT wc.id, wc.public_id, wc.user_id, u.public_id AS user_public_id, u.first_name, u.last_name,
       (round(wc.amount * 100))::bigint AS amount_cents,
       wc.reason, wcs.code AS status, wc.requested_at, wc.decided_at, wc.comment,
       du.first_name AS decided_by_first_name, du.last_name AS decided_by_last_name,
       pt.public_id AS payout_transaction_public_id
FROM welfare_claims wc
JOIN users u ON u.id = wc.user_id
JOIN welfare_claim_statuses wcs ON wcs.id = wc.status_id
LEFT JOIN users du ON du.id = wc.decided_by
LEFT JOIN transactions pt ON pt.id = wc.payout_transaction_id
WHERE wc.group_id = sqlc.arg(group_id)
  AND (sqlc.narg(user_id)::bigint IS NULL OR wc.user_id = sqlc.narg(user_id))
  AND (sqlc.narg(status)::text IS NULL OR wcs.code = sqlc.narg(status))
ORDER BY wc.requested_at DESC, wc.id DESC
LIMIT sqlc.arg(row_limit);

-- name: DecideWelfareClaim :execrows
UPDATE welfare_claims
SET status_id = (SELECT wcs.id FROM welfare_claim_statuses wcs WHERE wcs.code = sqlc.arg(status)),
    decided_by = sqlc.arg(decided_by), decided_at = now(), comment = sqlc.narg(comment)
WHERE group_id = sqlc.arg(group_id) AND public_id = sqlc.arg(public_id)
  AND status_id = (SELECT wcs.id FROM welfare_claim_statuses wcs WHERE wcs.code = 'pending');

-- name: LockWelfareClaim :one
SELECT wc.id, wc.user_id, wc.fund_id,
       (round(wc.amount * 100))::bigint AS amount_cents,
       wcs.code AS status
FROM welfare_claims wc
JOIN welfare_claim_statuses wcs ON wcs.id = wc.status_id
WHERE wc.group_id = sqlc.arg(group_id) AND wc.public_id = sqlc.arg(public_id)
FOR UPDATE OF wc;

-- name: LockWelfareFundBalance :one
SELECT wf.id,
       (COALESCE((
           SELECT round(sum(wc.amount) * 100)::bigint
           FROM welfare_contributions wc WHERE wc.fund_id = wf.id
       ), 0)::bigint - COALESCE((
           SELECT round(sum(t.amount) * 100)::bigint
           FROM transactions t
           JOIN transaction_types tt ON tt.id = t.transaction_type_id
           JOIN transaction_statuses ts ON ts.id = t.status_id
           WHERE t.group_id = wf.group_id AND tt.code = 'welfare_payout' AND ts.code = 'completed'
       ), 0)::bigint)::bigint AS balance_cents
FROM welfare_funds wf
WHERE wf.group_id = sqlc.arg(group_id)
FOR UPDATE OF wf;

-- name: MarkWelfareClaimPaid :execrows
UPDATE welfare_claims
SET status_id = (SELECT wcs.id FROM welfare_claim_statuses wcs WHERE wcs.code = 'paid'),
    payout_transaction_id = sqlc.arg(payout_transaction_id),
    decided_by = COALESCE(decided_by, sqlc.narg(decided_by)), decided_at = COALESCE(decided_at, now())
WHERE group_id = sqlc.arg(group_id) AND public_id = sqlc.arg(public_id)
  AND status_id = (SELECT wcs.id FROM welfare_claim_statuses wcs WHERE wcs.code = 'approved');
