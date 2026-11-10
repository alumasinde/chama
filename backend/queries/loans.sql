-- Loans: settings, applications, guarantors, approvals, schedules and repayments.

-- name: GetLoanSettings :one
SELECT s.group_id,
       trim(trailing '.' from trim(trailing '0' from s.interest_rate::text))::text AS interest_rate,
       im.code AS interest_method,
       trim(trailing '.' from trim(trailing '0' from s.max_multiple_of_savings::text))::text AS max_multiple,
       s.max_term_months,
       s.guarantors_required,
       s.allow_loans,
       s.updated_at
FROM group_loan_settings s
JOIN interest_methods im ON im.id = s.interest_method_id
WHERE s.group_id = sqlc.arg(group_id);

-- name: UpsertLoanSettings :exec
INSERT INTO group_loan_settings (
    group_id, interest_rate, interest_method_id, max_multiple_of_savings,
    max_term_months, guarantors_required, allow_loans
) VALUES (
    sqlc.arg(group_id),
    sqlc.arg(interest_rate)::text::numeric(6,3),
    (SELECT im2.id FROM interest_methods im2 WHERE im2.code = sqlc.arg(interest_method)),
    sqlc.arg(max_multiple)::text::numeric(6,2),
    sqlc.arg(max_term_months),
    sqlc.arg(guarantors_required),
    sqlc.arg(allow_loans)
)
ON CONFLICT (group_id) DO UPDATE
SET interest_rate = EXCLUDED.interest_rate,
    interest_method_id = EXCLUDED.interest_method_id,
    max_multiple_of_savings = EXCLUDED.max_multiple_of_savings,
    max_term_months = EXCLUDED.max_term_months,
    guarantors_required = EXCLUDED.guarantors_required,
    allow_loans = EXCLUDED.allow_loans,
    updated_at = now();

-- name: CreateLoan :one
INSERT INTO loans (
    group_id, user_id, principal, interest_rate, interest_method_id, term_months,
    status_id, total_interest, total_payable, purpose, created_by
) VALUES (
    sqlc.arg(group_id),
    sqlc.arg(user_id),
    (sqlc.arg(principal_cents)::bigint / 100.0)::numeric(15,2),
    sqlc.arg(interest_rate)::text::numeric(6,3),
    (SELECT im2.id FROM interest_methods im2 WHERE im2.code = sqlc.arg(interest_method)),
    sqlc.arg(term_months),
    (SELECT ls2.id FROM loan_statuses ls2 WHERE ls2.code = sqlc.arg(status)),
    (sqlc.arg(total_interest_cents)::bigint / 100.0)::numeric(15,2),
    (sqlc.arg(total_payable_cents)::bigint / 100.0)::numeric(15,2),
    sqlc.arg(purpose),
    sqlc.arg(created_by)
)
RETURNING id, public_id;

-- name: GetLoanByPublicID :one
SELECT l.id, l.public_id, l.user_id, u.public_id AS user_public_id, u.first_name, u.last_name,
       (round(l.principal * 100))::bigint AS principal_cents,
       trim(trailing '.' from trim(trailing '0' from l.interest_rate::text))::text AS interest_rate,
       im.code AS interest_method, l.term_months, ls.code AS status,
       (round(l.total_interest * 100))::bigint AS total_interest_cents,
       (round(l.total_payable * 100))::bigint AS total_payable_cents,
       (round(COALESCE((SELECT SUM(s.paid_amount) FROM loan_schedule_items s
                        WHERE s.loan_id = l.id), 0) * 100))::bigint AS paid_cents,
       l.purpose, l.requested_at, l.approved_at, l.disbursed_at, l.updated_at
FROM loans l
JOIN users u ON u.id = l.user_id
JOIN interest_methods im ON im.id = l.interest_method_id
JOIN loan_statuses ls ON ls.id = l.status_id
WHERE l.group_id = sqlc.arg(group_id) AND l.public_id = sqlc.arg(public_id);

-- name: ListLoans :many
SELECT l.id, l.public_id, l.user_id, u.public_id AS user_public_id, u.first_name, u.last_name,
       (round(l.principal * 100))::bigint AS principal_cents,
       trim(trailing '.' from trim(trailing '0' from l.interest_rate::text))::text AS interest_rate,
       im.code AS interest_method, l.term_months, ls.code AS status,
       (round(l.total_interest * 100))::bigint AS total_interest_cents,
       (round(l.total_payable * 100))::bigint AS total_payable_cents,
       (round(COALESCE((SELECT SUM(s.paid_amount) FROM loan_schedule_items s
                        WHERE s.loan_id = l.id), 0) * 100))::bigint AS paid_cents,
       l.purpose, l.requested_at, l.approved_at, l.disbursed_at, l.updated_at
FROM loans l
JOIN users u ON u.id = l.user_id
JOIN interest_methods im ON im.id = l.interest_method_id
JOIN loan_statuses ls ON ls.id = l.status_id
WHERE l.group_id = sqlc.arg(group_id)
  AND (sqlc.narg(user_id)::bigint IS NULL OR l.user_id = sqlc.narg(user_id))
  AND (sqlc.narg(status)::text IS NULL OR ls.code = sqlc.narg(status))
ORDER BY l.requested_at DESC, l.id DESC
LIMIT sqlc.arg(row_limit);

-- name: UpdateLoanStatus :execrows
UPDATE loans
SET status_id = (SELECT ls2.id FROM loan_statuses ls2 WHERE ls2.code = sqlc.arg(status)),
    approved_at = CASE WHEN sqlc.arg(status)::text = 'approved' AND approved_at IS NULL
        THEN now() ELSE approved_at END,
    disbursed_at = CASE WHEN sqlc.arg(status)::text = 'active' AND disbursed_at IS NULL
        THEN now() ELSE disbursed_at END,
    disbursement_transaction_id = COALESCE(sqlc.narg(disbursement_transaction_id), disbursement_transaction_id),
    updated_at = now()
WHERE loans.id = sqlc.arg(loan_id)
  AND loans.group_id = sqlc.arg(group_id)
  AND status_id = (SELECT ls2.id FROM loan_statuses ls2 WHERE ls2.code = sqlc.arg(expected_status));

-- name: AddLoanGuarantor :one
INSERT INTO loan_guarantors (group_id, loan_id, guarantor_user_id, amount_guaranteed, status_id)
VALUES (
    sqlc.arg(group_id),
    sqlc.arg(loan_id),
    sqlc.arg(guarantor_user_id),
    (sqlc.arg(amount_cents)::bigint / 100.0)::numeric(15,2),
    (SELECT gs2.id FROM guarantor_statuses gs2 WHERE gs2.code = 'pending')
)
ON CONFLICT (loan_id, guarantor_user_id) DO NOTHING
RETURNING id;

-- name: ListLoanGuarantors :many
SELECT lg.id, u.public_id AS user_public_id, u.first_name, u.last_name,
       (round(lg.amount_guaranteed * 100))::bigint AS amount_cents,
       gs.code AS status, lg.responded_at
FROM loan_guarantors lg
JOIN users u ON u.id = lg.guarantor_user_id
JOIN guarantor_statuses gs ON gs.id = lg.status_id
WHERE lg.group_id = sqlc.arg(group_id) AND lg.loan_id = sqlc.arg(loan_id)
ORDER BY lg.id;

-- name: RespondToGuarantor :execrows
UPDATE loan_guarantors lg
SET status_id = (SELECT gs2.id FROM guarantor_statuses gs2 WHERE gs2.code = sqlc.arg(decision)),
    responded_at = now()
WHERE lg.loan_id = sqlc.arg(loan_id)
  AND lg.group_id = sqlc.arg(group_id)
  AND lg.guarantor_user_id = sqlc.arg(guarantor_user_id)
  AND lg.status_id = (SELECT gs2.id FROM guarantor_statuses gs2 WHERE gs2.code = 'pending');

-- name: CountLoanGuarantors :one
SELECT (count(*) FILTER (WHERE gs.code = 'pending'))::bigint AS pending,
       (count(*) FILTER (WHERE gs.code = 'accepted'))::bigint AS accepted
FROM loan_guarantors lg
JOIN guarantor_statuses gs ON gs.id = lg.status_id
WHERE lg.loan_id = sqlc.arg(loan_id);

-- name: GuaranteeExposure :one
SELECT (round(COALESCE(SUM(lg.amount_guaranteed), 0) * 100))::bigint AS exposure_cents
FROM loan_guarantors lg
JOIN guarantor_statuses gs ON gs.id = lg.status_id
JOIN loans l ON l.id = lg.loan_id
JOIN loan_statuses ls ON ls.id = l.status_id
WHERE lg.group_id = sqlc.arg(group_id)
  AND lg.guarantor_user_id = sqlc.arg(guarantor_user_id)
  AND gs.code IN ('pending', 'accepted')
  AND ls.code IN ('pending_guarantors', 'pending_approval', 'approved', 'active');

-- name: MemberSavings :one
SELECT (round(COALESCE(SUM(
           CASE WHEN tt.code = 'contribution' THEN t.amount
                WHEN tt.code = 'reversal' THEN -t.amount
                ELSE 0 END), 0) * 100))::bigint AS savings_cents
FROM transactions t
JOIN transaction_types tt ON tt.id = t.transaction_type_id
JOIN transaction_statuses ts ON ts.id = t.status_id
WHERE t.group_id = sqlc.arg(group_id)
  AND t.user_id = sqlc.arg(user_id)
  AND ts.code = 'completed';

-- name: GetActiveMemberByPublicID :one
SELECT u.id, u.public_id, u.first_name, u.last_name
FROM users u
JOIN group_members gm ON gm.user_id = u.id
JOIN member_statuses ms ON ms.id = gm.status_id
WHERE u.public_id = sqlc.arg(public_id)
  AND gm.group_id = sqlc.arg(group_id)
  AND ms.code = 'active';

-- name: AddScheduleItem :exec
INSERT INTO loan_schedule_items (
    group_id, loan_id, installment_no, due_date, principal_due, interest_due
) VALUES (
    sqlc.arg(group_id),
    sqlc.arg(loan_id),
    sqlc.arg(installment_no),
    sqlc.arg(due_date)::text::date,
    (sqlc.arg(principal_cents)::bigint / 100.0)::numeric(15,2),
    (sqlc.arg(interest_cents)::bigint / 100.0)::numeric(15,2)
);

-- name: ListSchedule :many
SELECT id, installment_no, due_date::text AS due_date,
       (round(principal_due * 100))::bigint AS principal_cents,
       (round(interest_due * 100))::bigint AS interest_cents,
       (round(paid_amount * 100))::bigint AS paid_cents,
       paid_at
FROM loan_schedule_items
WHERE group_id = sqlc.arg(group_id) AND loan_id = sqlc.arg(loan_id)
ORDER BY installment_no;

-- name: ListScheduleForUpdate :many
SELECT id, installment_no, due_date::text AS due_date,
       (round(principal_due * 100))::bigint AS principal_cents,
       (round(interest_due * 100))::bigint AS interest_cents,
       (round(paid_amount * 100))::bigint AS paid_cents,
       paid_at
FROM loan_schedule_items
WHERE group_id = sqlc.arg(group_id) AND loan_id = sqlc.arg(loan_id)
ORDER BY installment_no
FOR UPDATE;

-- name: SetInstallmentPaid :exec
UPDATE loan_schedule_items
SET paid_amount = (sqlc.arg(paid_cents)::bigint / 100.0)::numeric(15,2),
    paid_at = CASE WHEN sqlc.arg(fully_paid)::boolean THEN now() ELSE paid_at END
WHERE loan_schedule_items.id = sqlc.arg(installment_id)
  AND loan_schedule_items.group_id = sqlc.arg(group_id);

-- name: UpsertLoanApproval :exec
INSERT INTO loan_approvals (group_id, loan_id, approver_id, decision_id, comment)
VALUES (
    sqlc.arg(group_id),
    sqlc.arg(loan_id),
    sqlc.arg(approver_id),
    (SELECT ad2.id FROM approval_decisions ad2 WHERE ad2.code = sqlc.arg(decision)),
    sqlc.narg(comment)
)
ON CONFLICT (loan_id, approver_id) DO UPDATE
SET decision_id = EXCLUDED.decision_id, comment = EXCLUDED.comment, created_at = now();

-- name: ListLoanApprovals :many
SELECT la.id, u.public_id AS approver_public_id, u.first_name, u.last_name,
       ad.code AS decision, la.comment, la.created_at
FROM loan_approvals la
JOIN users u ON u.id = la.approver_id
JOIN approval_decisions ad ON ad.id = la.decision_id
WHERE la.group_id = sqlc.arg(group_id) AND la.loan_id = sqlc.arg(loan_id)
ORDER BY la.id;

-- name: MarkDefaultedLoans :execrows
UPDATE loans l
SET status_id = (SELECT ls2.id FROM loan_statuses ls2 WHERE ls2.code = 'defaulted'),
    updated_at = now()
WHERE l.group_id = sqlc.arg(group_id)
  AND l.status_id = (SELECT ls2.id FROM loan_statuses ls2 WHERE ls2.code = 'active')
  AND EXISTS (
      SELECT 1 FROM loan_schedule_items s
      WHERE s.loan_id = l.id
        AND s.paid_at IS NULL
        AND s.due_date < CURRENT_DATE - sqlc.arg(overdue_days)::int
  );

-- name: ListGroupIDs :many
SELECT id, public_id FROM groups ORDER BY id;
