-- name: CreateOTP :one
INSERT INTO otp_codes (phone_number, code_hash, purpose_id, expires_at, request_ip)
VALUES (
    sqlc.arg(phone_number),
    sqlc.arg(code_hash),
    (SELECT id FROM otp_purposes WHERE code = sqlc.arg(purpose)),
    now() + make_interval(secs => sqlc.arg(ttl_seconds)::int),
    sqlc.narg(request_ip)
)
RETURNING id, expires_at;

-- name: LatestOTP :one
SELECT o.id, o.code_hash, o.expires_at, o.consumed_at, o.attempts
FROM otp_codes o
JOIN otp_purposes p ON p.id = o.purpose_id
WHERE o.phone_number = sqlc.arg(phone_number)
  AND p.code = sqlc.arg(purpose)
ORDER BY o.id DESC
LIMIT 1;

-- name: ConsumeOTP :execrows
UPDATE otp_codes SET consumed_at = now()
WHERE id = sqlc.arg(id) AND consumed_at IS NULL;

-- name: IncrementOTPAttempts :one
UPDATE otp_codes SET attempts = attempts + 1
WHERE id = sqlc.arg(id)
RETURNING attempts;

-- name: CreateRefreshToken :one
INSERT INTO refresh_tokens (user_id, token_hash, session_id, device_id, expires_at, user_agent, ip)
VALUES (
    sqlc.arg(user_id),
    sqlc.arg(token_hash),
    sqlc.arg(session_id),
    sqlc.narg(device_id),
    now() + make_interval(secs => sqlc.arg(ttl_seconds)::int),
    sqlc.narg(user_agent),
    sqlc.narg(ip)
)
RETURNING id, expires_at;

-- name: GetRefreshToken :one
SELECT id, user_id, session_id, expires_at, revoked_at, replaced_by
FROM refresh_tokens
WHERE token_hash = sqlc.arg(token_hash);

-- name: RotateRefreshToken :execrows
UPDATE refresh_tokens
SET revoked_at = now(), replaced_by = sqlc.arg(replaced_by)
WHERE id = sqlc.arg(id) AND revoked_at IS NULL;

-- name: RevokeSession :exec
UPDATE refresh_tokens SET revoked_at = now()
WHERE session_id = sqlc.arg(session_id) AND revoked_at IS NULL;

-- name: RevokeAllUserTokens :exec
UPDATE refresh_tokens SET revoked_at = now()
WHERE user_id = sqlc.arg(user_id) AND revoked_at IS NULL;

-- name: UpsertPIN :exec
INSERT INTO user_pins (user_id, pin_hash)
VALUES (sqlc.arg(user_id), sqlc.arg(pin_hash))
ON CONFLICT (user_id) DO UPDATE
SET pin_hash = EXCLUDED.pin_hash,
    failed_attempts = 0,
    locked_until = NULL,
    updated_at = now();

-- name: GetPIN :one
SELECT pin_hash, failed_attempts, locked_until
FROM user_pins WHERE user_id = sqlc.arg(user_id);

-- name: RecordPINFailure :one
UPDATE user_pins
SET failed_attempts = failed_attempts + 1,
    locked_until = CASE
        WHEN failed_attempts + 1 >= sqlc.arg(max_attempts)::int
        THEN now() + make_interval(secs => sqlc.arg(lock_seconds)::int)
        ELSE locked_until
    END,
    updated_at = now()
WHERE user_id = sqlc.arg(user_id)
RETURNING failed_attempts, locked_until;

-- name: ResetPINFailures :exec
UPDATE user_pins
SET failed_attempts = 0, locked_until = NULL, updated_at = now()
WHERE user_id = sqlc.arg(user_id);

-- name: GetThrottle :one
SELECT attempts, window_start, locked_until
FROM auth_throttle WHERE key = sqlc.arg(key);

-- name: BumpThrottle :one
INSERT INTO auth_throttle (key, window_start, attempts, updated_at)
VALUES (sqlc.arg(key), now(), 1, now())
ON CONFLICT (key) DO UPDATE
SET attempts = CASE
        WHEN auth_throttle.window_start < now() - make_interval(secs => sqlc.arg(window_seconds)::int)
        THEN 1 ELSE auth_throttle.attempts + 1
    END,
    window_start = CASE
        WHEN auth_throttle.window_start < now() - make_interval(secs => sqlc.arg(window_seconds)::int)
        THEN now() ELSE auth_throttle.window_start
    END,
    updated_at = now()
RETURNING attempts, locked_until;

-- name: LockThrottle :exec
UPDATE auth_throttle
SET locked_until = now() + make_interval(secs => sqlc.arg(lock_seconds)::int)
WHERE key = sqlc.arg(key);

-- name: ClearThrottle :exec
DELETE FROM auth_throttle WHERE key = sqlc.arg(key);

-- name: CreateDevice :one
INSERT INTO user_devices (user_id, device_token, platform_id, device_name, biometric_enabled)
VALUES (
    sqlc.arg(user_id),
    sqlc.narg(device_token),
    (SELECT id FROM device_platforms WHERE code = sqlc.arg(platform)),
    sqlc.narg(device_name),
    sqlc.arg(biometric_enabled)
)
RETURNING id, public_id;

-- name: ListDevices :many
SELECT d.id, d.public_id, p.code AS platform, d.device_name, d.biometric_enabled,
       d.last_seen_at, d.created_at
FROM user_devices d
JOIN device_platforms p ON p.id = d.platform_id
WHERE d.user_id = sqlc.arg(user_id)
ORDER BY d.id DESC;

-- name: DeleteDevice :execrows
DELETE FROM user_devices
WHERE user_id = sqlc.arg(user_id) AND public_id = sqlc.arg(public_id);
