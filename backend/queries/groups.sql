-- name: CreateGroup :one
WITH created AS (
    INSERT INTO groups (
        name, invite_code, description, currency_code, contribution_amount,
        contribution_frequency_id, contribution_day, late_grace_days, created_by
    ) VALUES (
        sqlc.arg(name),
        sqlc.arg(invite_code),
        sqlc.narg(description),
        'KES',
        (sqlc.arg(contribution_amount_cents)::bigint / 100.0)::numeric(15,2),
        (SELECT f.id FROM contribution_frequencies f WHERE f.code = sqlc.arg(frequency)),
        sqlc.arg(contribution_day),
        sqlc.arg(late_grace_days),
        sqlc.arg(created_by)
    )
    RETURNING *
)
SELECT g.id, g.public_id, g.name, g.invite_code, g.description,
       (round(g.contribution_amount * 100))::bigint AS contribution_amount_cents,
       cf.code AS frequency, g.contribution_day, g.late_grace_days, g.created_at
FROM created g
JOIN contribution_frequencies cf ON cf.id = g.contribution_frequency_id;

-- name: GetGroupByPublicID :one
SELECT g.id, g.public_id, g.name, g.invite_code, g.description,
       (round(g.contribution_amount * 100))::bigint AS contribution_amount_cents,
       cf.code AS frequency, g.contribution_day, g.late_grace_days, g.created_at
FROM groups g
JOIN contribution_frequencies cf ON cf.id = g.contribution_frequency_id
WHERE g.public_id = sqlc.arg(public_id);

-- name: GetGroupByInviteCode :one
SELECT g.id, g.public_id, g.name, g.invite_code, g.description,
       (round(g.contribution_amount * 100))::bigint AS contribution_amount_cents,
       cf.code AS frequency, g.contribution_day, g.late_grace_days, g.created_at
FROM groups g
JOIN contribution_frequencies cf ON cf.id = g.contribution_frequency_id
WHERE g.invite_code = sqlc.arg(invite_code);

-- name: UpdateGroup :one
WITH updated AS (
    UPDATE groups
    SET name = sqlc.arg(name),
        description = sqlc.narg(description),
        contribution_amount = (sqlc.arg(contribution_amount_cents)::bigint / 100.0)::numeric(15,2),
        contribution_frequency_id = (SELECT f.id FROM contribution_frequencies f WHERE f.code = sqlc.arg(frequency)),
        contribution_day = sqlc.arg(contribution_day),
        late_grace_days = sqlc.arg(late_grace_days),
        updated_at = now()
    WHERE groups.id = sqlc.arg(id)
    RETURNING *
)
SELECT g.id, g.public_id, g.name, g.invite_code, g.description,
       (round(g.contribution_amount * 100))::bigint AS contribution_amount_cents,
       cf.code AS frequency, g.contribution_day, g.late_grace_days, g.created_at
FROM updated g
JOIN contribution_frequencies cf ON cf.id = g.contribution_frequency_id;

-- name: RotateInviteCode :exec
UPDATE groups SET invite_code = sqlc.arg(invite_code), updated_at = now()
WHERE groups.id = sqlc.arg(id);

-- name: ListGroupsForUser :many
SELECT g.id, g.public_id, g.name, g.invite_code, g.description,
       (round(g.contribution_amount * 100))::bigint AS contribution_amount_cents,
       cf.code AS frequency, g.contribution_day, g.late_grace_days, g.created_at,
       r.code AS role, ms.code AS status,
       (SELECT count(*) FROM group_members gm
        JOIN member_statuses ams ON ams.id = gm.status_id
        WHERE gm.group_id = g.id AND ams.code = 'active') AS active_members
FROM group_members m
JOIN groups g ON g.id = m.group_id
JOIN member_roles r ON r.id = m.role_id
JOIN member_statuses ms ON ms.id = m.status_id
JOIN contribution_frequencies cf ON cf.id = g.contribution_frequency_id
WHERE m.user_id = sqlc.arg(user_id)
ORDER BY g.name;

-- name: CountActiveMembers :one
SELECT count(*)
FROM group_members m
JOIN member_statuses s ON s.id = m.status_id
WHERE m.group_id = sqlc.arg(group_id) AND s.code = 'active';

-- name: GetMembership :one
SELECT m.id, m.group_id, m.user_id, r.code AS role, ms.code AS status, m.joined_at
FROM group_members m
JOIN member_roles r ON r.id = m.role_id
JOIN member_statuses ms ON ms.id = m.status_id
WHERE m.group_id = sqlc.arg(group_id) AND m.user_id = sqlc.arg(user_id);

-- name: CreateMembership :one
INSERT INTO group_members (group_id, user_id, role_id, status_id)
VALUES (
    sqlc.arg(group_id),
    sqlc.arg(user_id),
    (SELECT r2.id FROM member_roles r2 WHERE r2.code = sqlc.arg(role)),
    (SELECT s2.id FROM member_statuses s2 WHERE s2.code = sqlc.arg(status))
)
RETURNING id, group_id, user_id;

-- name: UpdateMembershipState :execrows
UPDATE group_members
SET role_id = (SELECT r2.id FROM member_roles r2 WHERE r2.code = sqlc.arg(role)),
    status_id = (SELECT s2.id FROM member_statuses s2 WHERE s2.code = sqlc.arg(status)),
    joined_at = CASE WHEN sqlc.arg(joined)::boolean AND joined_at IS NULL THEN now() ELSE joined_at END,
    exited_at = CASE WHEN sqlc.arg(exited)::boolean THEN now() ELSE exited_at END,
    approved_by = COALESCE(sqlc.narg(approved_by), approved_by),
    updated_at = now()
WHERE group_id = sqlc.arg(group_id) AND user_id = sqlc.arg(user_id);

-- name: GetGroupMember :one
SELECT u.public_id AS user_public_id, u.first_name, u.last_name,
       r.code AS role, ms.code AS status, m.joined_at
FROM group_members m
JOIN users u ON u.id = m.user_id
JOIN member_roles r ON r.id = m.role_id
JOIN member_statuses ms ON ms.id = m.status_id
WHERE m.group_id = sqlc.arg(group_id) AND m.user_id = sqlc.arg(user_id);

-- name: ListGroupMembers :many
SELECT u.public_id AS user_public_id, u.first_name, u.last_name,
       r.code AS role, ms.code AS status, m.joined_at
FROM group_members m
JOIN users u ON u.id = m.user_id
JOIN member_roles r ON r.id = m.role_id
JOIN member_statuses ms ON ms.id = m.status_id
WHERE m.group_id = sqlc.arg(group_id)
ORDER BY m.id;

-- name: CountActiveAdmins :one
SELECT count(*)
FROM group_members m
JOIN member_roles r ON r.id = m.role_id
JOIN member_statuses s ON s.id = m.status_id
WHERE m.group_id = sqlc.arg(group_id)
  AND r.code = 'admin' AND s.code = 'active';

-- name: GetUserIDByPublicID :one
SELECT id FROM users WHERE public_id = sqlc.arg(public_id);

-- name: GetPaymentSettings :one
SELECT s.group_id, st.code AS shortcode_type, s.shortcode, s.account_reference_template,
       de.code AS daraja_environment,
       s.daraja_consumer_key_enc, s.daraja_consumer_secret_enc,
       s.daraja_passkey_enc, s.callback_secret_enc,
       s.is_verified, s.verified_at, s.updated_at
FROM group_payment_settings s
JOIN payment_shortcode_types st ON st.id = s.shortcode_type_id
JOIN daraja_environments de ON de.id = s.daraja_environment_id
WHERE s.group_id = sqlc.arg(group_id);

-- name: UpsertPaymentSettings :exec
INSERT INTO group_payment_settings (
    group_id, shortcode_type_id, shortcode, account_reference_template,
    daraja_environment_id, daraja_consumer_key_enc, daraja_consumer_secret_enc,
    daraja_passkey_enc, callback_secret_enc, is_verified, verified_at, updated_by
) VALUES (
    sqlc.arg(group_id),
    (SELECT t.id FROM payment_shortcode_types t WHERE t.code = sqlc.arg(shortcode_type)),
    sqlc.arg(shortcode),
    sqlc.arg(account_reference_template),
    (SELECT e.id FROM daraja_environments e WHERE e.code = sqlc.arg(daraja_environment)),
    sqlc.arg(daraja_consumer_key_enc),
    sqlc.arg(daraja_consumer_secret_enc),
    sqlc.arg(daraja_passkey_enc),
    sqlc.arg(callback_secret_enc),
    FALSE,
    NULL,
    sqlc.arg(updated_by)
)
ON CONFLICT (group_id) DO UPDATE
SET shortcode_type_id = EXCLUDED.shortcode_type_id,
    shortcode = EXCLUDED.shortcode,
    account_reference_template = EXCLUDED.account_reference_template,
    daraja_environment_id = EXCLUDED.daraja_environment_id,
    daraja_consumer_key_enc = EXCLUDED.daraja_consumer_key_enc,
    daraja_consumer_secret_enc = EXCLUDED.daraja_consumer_secret_enc,
    daraja_passkey_enc = EXCLUDED.daraja_passkey_enc,
    callback_secret_enc = EXCLUDED.callback_secret_enc,
    is_verified = FALSE,
    verified_at = NULL,
    updated_by = EXCLUDED.updated_by,
    updated_at = now();
