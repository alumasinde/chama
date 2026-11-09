-- name: CreateUser :one
INSERT INTO users (phone_number, first_name, last_name, email, national_id_enc, password_hash)
VALUES (
    sqlc.arg(phone_number),
    sqlc.arg(first_name),
    sqlc.arg(last_name),
    sqlc.narg(email),
    sqlc.narg(national_id_enc),
    sqlc.narg(password_hash)
)
RETURNING *;

-- name: GetUserByPublicID :one
SELECT * FROM users WHERE public_id = sqlc.arg(public_id);

-- name: GetUserByID :one
SELECT * FROM users WHERE id = sqlc.arg(id);

-- name: GetUserByPhone :one
SELECT * FROM users WHERE phone_number = sqlc.arg(phone_number);

-- name: UpdateUserProfile :one
UPDATE users
SET first_name = sqlc.arg(first_name),
    last_name = sqlc.arg(last_name),
    email = sqlc.narg(email),
    updated_at = now()
WHERE id = sqlc.arg(id)
RETURNING *;

-- name: SetUserNationalID :exec
UPDATE users SET national_id_enc = sqlc.arg(national_id_enc), updated_at = now()
WHERE id = sqlc.arg(id);

-- name: SetUserPassword :exec
UPDATE users SET password_hash = sqlc.arg(password_hash), updated_at = now()
WHERE id = sqlc.arg(id);

-- name: TouchPhoneVerified :exec
UPDATE users SET phone_verified_at = COALESCE(phone_verified_at, now()), updated_at = now()
WHERE id = sqlc.arg(id);
