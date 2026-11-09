-- Per-chama Daraja credentials, AES-256-GCM encrypted with a group-bound AAD.

CREATE TABLE group_payment_settings (
    group_id BIGINT PRIMARY KEY REFERENCES groups(id) ON DELETE CASCADE,
    shortcode_type_id SMALLINT NOT NULL REFERENCES payment_shortcode_types(id),
    shortcode TEXT NOT NULL,
    account_reference_template TEXT NOT NULL DEFAULT 'CHAMA-{member_short}-{period}',
    daraja_environment_id SMALLINT NOT NULL REFERENCES daraja_environments(id),
    daraja_consumer_key_enc BYTEA NOT NULL,
    daraja_consumer_secret_enc BYTEA NOT NULL,
    daraja_passkey_enc BYTEA NOT NULL,
    callback_secret_enc BYTEA NOT NULL,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMPTZ,
    updated_by BIGINT REFERENCES users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
