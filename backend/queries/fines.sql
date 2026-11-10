-- Fines: rules, custom fines, waivers, manual payments and the evaluation job.

-- name: GetFineRuleByType :one
SELECT fr.id, ft.code AS fine_type, fcm.code AS calculation_method,
       trim(trailing '.' from trim(trailing '0' from fr.amount_or_rate::text))::text AS amount_or_rate,
       fr.grace_days, fr.is_active, fr.updated_at
FROM fine_rules fr
JOIN fine_types ft ON ft.id = fr.fine_type_id
JOIN fine_calculation_methods fcm ON fcm.id = fr.calculation_method_id
WHERE fr.group_id = sqlc.arg(group_id)
  AND ft.code = sqlc.arg(fine_type)
  AND fr.is_active;

-- name: ListFineRules :many
SELECT fr.id, ft.code AS fine_type, fcm.code AS calculation_method,
       trim(trailing '.' from trim(trailing '0' from fr.amount_or_rate::text))::text AS amount_or_rate,
       fr.grace_days, fr.is_active, fr.updated_at
FROM fine_rules fr
JOIN fine_types ft ON ft.id = fr.fine_type_id
JOIN fine_calculation_methods fcm ON fcm.id = fr.calculation_method_id
WHERE fr.group_id = sqlc.arg(group_id)
ORDER BY ft.sort_order;

-- name: InsertFineRule :one
INSERT INTO fine_rules (group_id, fine_type_id, calculation_method_id, amount_or_rate, grace_days)
VALUES (
    sqlc.arg(group_id),
    (SELECT ft2.id FROM fine_types ft2 WHERE ft2.code = sqlc.arg(fine_type)),
    (SELECT fcm2.id FROM fine_calculation_methods fcm2 WHERE fcm2.code = sqlc.arg(calculation_method)),
    sqlc.arg(amount_or_rate)::text::numeric(15,2),
    sqlc.arg(grace_days)
)
RETURNING id;

-- name: UpdateFineRule :exec
UPDATE fine_rules
SET calculation_method_id = (SELECT fcm2.id FROM fine_calculation_methods fcm2 WHERE fcm2.code = sqlc.arg(calculation_method)),
    amount_or_rate = sqlc.arg(amount_or_rate)::text::numeric(15,2),
    grace_days = sqlc.arg(grace_days),
    updated_at = now()
WHERE fine_rules.id = sqlc.arg(fine_rule_id)
  AND fine_rules.group_id = sqlc.arg(group_id);

-- name: CreateFine :one
INSERT INTO fines (
    group_id, user_id, fine_rule_id, fine_type_id, amount, reason, status_id, period_label
) VALUES (
    sqlc.arg(group_id),
    sqlc.arg(user_id),
    sqlc.narg(fine_rule_id),
    (SELECT ft2.id FROM fine_types ft2 WHERE ft2.code = sqlc.arg(fine_type)),
    (sqlc.arg(amount_cents)::bigint / 100.0)::numeric(15,2),
    sqlc.arg(reason),
    (SELECT fs2.id FROM fine_statuses fs2 WHERE fs2.code = 'unpaid'),
    sqlc.narg(period_label)
)
RETURNING id, public_id;

-- name: GetFineByPublicID :one
SELECT f.id, f.public_id, f.user_id, u.public_id AS user_public_id, u.first_name, u.last_name,
       ft.code AS fine_type,
       (round(f.amount * 100))::bigint AS amount_cents,
       f.reason, fs.code AS status, f.period_label,
       f.assessed_on::text AS assessed_on,
       f.waive_reason,
       (f.payment_transaction_id IS NOT NULL)::boolean AS paid,
       f.created_at
FROM fines f
JOIN users u ON u.id = f.user_id
JOIN fine_types ft ON ft.id = f.fine_type_id
JOIN fine_statuses fs ON fs.id = f.status_id
WHERE f.group_id = sqlc.arg(group_id) AND f.public_id = sqlc.arg(public_id);

-- name: ListFines :many
SELECT f.id, f.public_id, u.public_id AS user_public_id, u.first_name, u.last_name,
       ft.code AS fine_type,
       (round(f.amount * 100))::bigint AS amount_cents,
       f.reason, fs.code AS status, f.period_label,
       f.assessed_on::text AS assessed_on,
       f.waive_reason,
       (f.payment_transaction_id IS NOT NULL)::boolean AS paid,
       f.created_at
FROM fines f
JOIN users u ON u.id = f.user_id
JOIN fine_types ft ON ft.id = f.fine_type_id
JOIN fine_statuses fs ON fs.id = f.status_id
WHERE f.group_id = sqlc.arg(group_id)
  AND (sqlc.narg(user_id)::bigint IS NULL OR f.user_id = sqlc.narg(user_id))
  AND (sqlc.narg(status)::text IS NULL OR fs.code = sqlc.narg(status))
ORDER BY f.created_at DESC, f.id DESC
LIMIT sqlc.arg(row_limit);

-- name: WaiveFine :execrows
UPDATE fines
SET status_id = (SELECT fs2.id FROM fine_statuses fs2 WHERE fs2.code = 'waived'),
    waived_by = sqlc.arg(waived_by),
    waive_reason = sqlc.arg(waive_reason)
WHERE group_id = sqlc.arg(group_id)
  AND public_id = sqlc.arg(public_id)
  AND status_id = (SELECT fs2.id FROM fine_statuses fs2 WHERE fs2.code = 'unpaid');

-- name: MarkFinePaid :execrows
UPDATE fines
SET status_id = (SELECT fs2.id FROM fine_statuses fs2 WHERE fs2.code = 'paid'),
    payment_transaction_id = sqlc.arg(payment_transaction_id)
WHERE group_id = sqlc.arg(group_id)
  AND public_id = sqlc.arg(public_id)
  AND status_id = (SELECT fs2.id FROM fine_statuses fs2 WHERE fs2.code = 'unpaid');

-- name: CreateEvaluatedFines :execrows
INSERT INTO fines (
    group_id, user_id, fine_rule_id, fine_type_id, amount, reason, status_id,
    period_label, assessed_on
)
SELECT fr.group_id, gm.user_id, fr.id, fr.fine_type_id,
       CASE WHEN fcm.code = 'percentage'
            THEN round(g.contribution_amount * fr.amount_or_rate / 100.0, 2)
            ELSE fr.amount_or_rate END,
       'Contribution not recorded for ' || sqlc.arg(period_label)::text,
       (SELECT fs2.id FROM fine_statuses fs2 WHERE fs2.code = 'unpaid'),
       sqlc.arg(period_label),
       CURRENT_DATE
FROM fine_rules fr
JOIN fine_types ft ON ft.id = fr.fine_type_id
JOIN fine_calculation_methods fcm ON fcm.id = fr.calculation_method_id
JOIN groups g ON g.id = fr.group_id
JOIN group_members gm ON gm.group_id = fr.group_id
JOIN member_statuses ms ON ms.id = gm.status_id AND ms.code = 'active'
WHERE fr.group_id = sqlc.arg(group_id)
  AND fr.is_active
  AND ft.code = 'late_contribution'
  AND (sqlc.arg(period_end)::timestamptz + make_interval(days => fr.grace_days)) <= now()
  AND NOT EXISTS (
      SELECT 1 FROM fines f
      WHERE f.group_id = fr.group_id AND f.user_id = gm.user_id
        AND f.fine_rule_id = fr.id AND f.period_label = sqlc.arg(period_label)
  )
  AND NOT EXISTS (
      SELECT 1 FROM transactions t
      JOIN transaction_types tt ON tt.id = t.transaction_type_id
      JOIN transaction_statuses ts ON ts.id = t.status_id
      WHERE t.group_id = fr.group_id AND t.user_id = gm.user_id
        AND tt.code = 'contribution' AND ts.code = 'completed'
        AND t.created_at >= sqlc.arg(period_start)::timestamptz
        AND t.created_at < sqlc.arg(period_end)::timestamptz
  )
ON CONFLICT DO NOTHING;

-- name: GetFineGroup :one
SELECT g.id, g.public_id,
       (round(g.contribution_amount * 100))::bigint AS contribution_cents,
       cf.code AS frequency, g.contribution_day, g.late_grace_days
FROM groups g
JOIN contribution_frequencies cf ON cf.id = g.contribution_frequency_id
WHERE g.id = sqlc.arg(group_id);

-- name: ListFineGroups :many
SELECT g.id, g.public_id,
       (round(g.contribution_amount * 100))::bigint AS contribution_cents,
       cf.code AS frequency, g.contribution_day, g.late_grace_days
FROM groups g
JOIN contribution_frequencies cf ON cf.id = g.contribution_frequency_id
ORDER BY g.id;
