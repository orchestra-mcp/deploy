-- 002_create_users.sql
-- Core user tables: users, passkeys, OAuth accounts, device tokens, OTP codes,
-- magic link tokens, user verifications, and verification types.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Users
-- =============================================================================

CREATE TABLE IF NOT EXISTS users (
    id              BIGSERIAL       PRIMARY KEY,
    email           TEXT            UNIQUE NOT NULL,
    password        TEXT            DEFAULT '',
    name            TEXT            DEFAULT '',
    handle          TEXT            UNIQUE DEFAULT '',
    role            TEXT            DEFAULT 'user'
                                    CHECK (role IN ('admin', 'team_owner', 'team_manager', 'user')),
    avatar          TEXT            DEFAULT '',
    bio             TEXT            DEFAULT '',
    status          TEXT            DEFAULT 'active'
                                    CHECK (status IN ('active', 'inactive', 'suspended', 'banned')),
    timezone        TEXT            DEFAULT 'UTC',
    github_email    TEXT            DEFAULT '',
    two_factor_enabled  BOOLEAN    DEFAULT false,
    two_factor_secret   TEXT       DEFAULT '',
    email_verified      BOOLEAN    DEFAULT false,
    email_verified_at   TIMESTAMPTZ,
    last_login_at       TIMESTAMPTZ,
    settings        JSONB           DEFAULT '{}',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_users_email           ON users (email);
CREATE INDEX IF NOT EXISTS idx_users_handle          ON users (handle);
CREATE INDEX IF NOT EXISTS idx_users_role            ON users (role);
CREATE INDEX IF NOT EXISTS idx_users_status          ON users (status);
CREATE INDEX IF NOT EXISTS idx_users_deleted_at      ON users (deleted_at);

COMMENT ON TABLE users IS 'Core user accounts';
COMMENT ON COLUMN users.role IS 'One of: admin, team_owner, team_manager, user';

-- =============================================================================
-- Passkeys (WebAuthn / FIDO2)
-- =============================================================================

CREATE TABLE IF NOT EXISTS passkeys (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    credential_id   TEXT            UNIQUE NOT NULL,
    public_key      BYTEA           NOT NULL,
    aaguid          TEXT            DEFAULT '',
    sign_count      INTEGER         DEFAULT 0,
    transports      TEXT[]          DEFAULT '{}',
    name            TEXT            DEFAULT '',
    last_used_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_passkeys_user_id       ON passkeys (user_id);
CREATE INDEX IF NOT EXISTS idx_passkeys_credential_id ON passkeys (credential_id);

COMMENT ON TABLE passkeys IS 'WebAuthn / FIDO2 passkey credentials';

-- =============================================================================
-- OAuth Accounts
-- =============================================================================

CREATE TABLE IF NOT EXISTS oauth_accounts (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider        TEXT            NOT NULL,
    provider_id     TEXT            NOT NULL,
    access_token    TEXT            DEFAULT '',
    refresh_token   TEXT            DEFAULT '',
    token_expiry    TIMESTAMPTZ,
    scopes          TEXT[]          DEFAULT '{}',
    profile         JSONB           DEFAULT '{}',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_oauth_accounts_provider_user
    ON oauth_accounts (provider, user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_oauth_accounts_provider_id
    ON oauth_accounts (provider, provider_id);

COMMENT ON TABLE oauth_accounts IS 'Third-party OAuth provider links (GitHub, Google, etc.)';

-- =============================================================================
-- Device Tokens (push notifications)
-- =============================================================================

CREATE TABLE IF NOT EXISTS device_tokens (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token           TEXT            NOT NULL,
    platform        TEXT            NOT NULL
                                    CHECK (platform IN ('ios', 'android', 'web', 'macos', 'windows', 'linux')),
    device_name     TEXT            DEFAULT '',
    app_version     TEXT            DEFAULT '',
    last_active_at  TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id  ON device_tokens (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_device_tokens_token
    ON device_tokens (token);

COMMENT ON TABLE device_tokens IS 'Push notification device tokens per platform';

-- =============================================================================
-- OTP Codes (two-factor and email verification)
-- =============================================================================

CREATE TABLE IF NOT EXISTS otp_codes (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code            TEXT            NOT NULL,
    purpose         TEXT            NOT NULL DEFAULT 'login'
                                    CHECK (purpose IN ('login', 'email_verify', 'password_reset', 'two_factor')),
    expires_at      TIMESTAMPTZ     NOT NULL,
    used_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_otp_codes_user_id     ON otp_codes (user_id);
CREATE INDEX IF NOT EXISTS idx_otp_codes_expires_at  ON otp_codes (expires_at);

COMMENT ON TABLE otp_codes IS 'One-time password codes for various verification purposes';

-- =============================================================================
-- Magic Link Tokens
-- =============================================================================

CREATE TABLE IF NOT EXISTS magic_link_tokens (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token           TEXT            UNIQUE NOT NULL,
    purpose         TEXT            NOT NULL DEFAULT 'login'
                                    CHECK (purpose IN ('login', 'email_verify', 'invite')),
    expires_at      TIMESTAMPTZ     NOT NULL,
    used_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_magic_link_tokens_user_id ON magic_link_tokens (user_id);
CREATE INDEX IF NOT EXISTS idx_magic_link_tokens_token   ON magic_link_tokens (token);

COMMENT ON TABLE magic_link_tokens IS 'Passwordless magic-link authentication tokens';

-- =============================================================================
-- Verification Types (lookup)
-- =============================================================================

CREATE TABLE IF NOT EXISTS verification_types (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT            UNIQUE NOT NULL,
    description     TEXT            DEFAULT '',
    ttl_seconds     INTEGER         DEFAULT 3600,
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

COMMENT ON TABLE verification_types IS 'Lookup table for verification type definitions';

-- Seed default verification types
INSERT INTO verification_types (name, description, ttl_seconds)
VALUES
    ('email',          'Email address verification',      86400),
    ('phone',          'Phone number verification',       600),
    ('identity',       'Government ID verification',      0),
    ('two_factor',     'Two-factor authentication setup', 300)
ON CONFLICT (name) DO NOTHING;

-- =============================================================================
-- User Verifications
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_verifications (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    verification_type   TEXT        NOT NULL,
    token               TEXT        UNIQUE NOT NULL,
    verified            BOOLEAN     DEFAULT false,
    verified_at         TIMESTAMPTZ,
    expires_at          TIMESTAMPTZ NOT NULL,
    metadata            JSONB       DEFAULT '{}',
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_verifications_user_id ON user_verifications (user_id);
CREATE INDEX IF NOT EXISTS idx_user_verifications_token   ON user_verifications (token);

COMMENT ON TABLE user_verifications IS 'Tracks user verification attempts and status';
