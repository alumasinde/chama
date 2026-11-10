-- In-app notifications, read state and the reminder query for due contributions.

-- name: InsertNotification :one
INSERT INTO notifications (user_id, group_id, type_id, title, body, data, dedupe_key)
VALUES (
    sqlc.arg(user_id), sqlc.narg(group_id),
    (SELECT nt.id FROM notification_types nt WHERE nt.code = sqlc.arg(notification_type)),
    sqlc.arg(title), sqlc.arg(body),
    COALESCE(sqlc.arg(data)::text::jsonb, '{}'::jsonb),
    sqlc.narg(dedupe_key)
)
ON CONFLICT (user_id, dedupe_key) DO NOTHING
RETURNING public_id, created_at;

-- name: ListNotifications :many
SELECT n.public_id, nt.code AS notification_type, n.title, n.body, n.data,
       n.read_at, n.created_at
FROM notifications n
JOIN notification_types nt ON nt.id = n.type_id
WHERE n.user_id = sqlc.arg(user_id)
  AND (sqlc.arg(unread_only)::boolean = FALSE OR n.read_at IS NULL)
ORDER BY n.created_at DESC, n.id DESC
LIMIT sqlc.arg(row_limit);

-- name: CountUnreadNotifications :one
SELECT count(*)::bigint FROM notifications WHERE user_id = sqlc.arg(user_id) AND read_at IS NULL;

-- name: MarkNotificationRead :execrows
UPDATE notifications SET read_at = now()
WHERE user_id = sqlc.arg(user_id) AND public_id = sqlc.arg(public_id) AND read_at IS NULL;

-- name: MarkAllNotificationsRead :execrows
UPDATE notifications SET read_at = now()
WHERE user_id = sqlc.arg(user_id) AND read_at IS NULL;

-- name: MarkNotificationPushed :exec
UPDATE notifications SET pushed_at = now()
WHERE user_id = sqlc.arg(user_id) AND public_id = sqlc.arg(public_id);

-- name: ListNotificationDeviceTokens :many
SELECT device_token FROM user_devices
WHERE user_id = sqlc.arg(user_id) AND device_token IS NOT NULL AND device_token <> '';

-- name: ListGroupCadences :many
SELECT g.id AS group_id, g.public_id, g.name, cf.code AS frequency
FROM groups g JOIN contribution_frequencies cf ON cf.id = g.contribution_frequency_id
ORDER BY g.id;

-- name: ListMembersWithoutContribution :many
SELECT gm.user_id, u.public_id AS user_public_id, u.first_name, u.last_name
FROM group_members gm
JOIN users u ON u.id = gm.user_id
JOIN member_statuses ms ON ms.id = gm.status_id
WHERE gm.group_id = sqlc.arg(group_id) AND ms.code = 'active'
  AND NOT EXISTS (
      SELECT 1 FROM transactions t
      JOIN transaction_types tt ON tt.id = t.transaction_type_id
      JOIN transaction_statuses ts ON ts.id = t.status_id
      WHERE t.group_id = gm.group_id AND t.user_id = gm.user_id
        AND tt.code = 'contribution' AND ts.code = 'completed'
        AND t.created_at >= sqlc.arg(period_start)::timestamptz
        AND t.created_at < sqlc.arg(period_end)::timestamptz
  )
ORDER BY gm.id;
