-- 010_create_settings.sql
-- User settings, system settings, subscriptions, integrations, push subscriptions.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- User Settings
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_settings (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key             TEXT            NOT NULL DEFAULT '',
    value           JSONB           DEFAULT '{}',
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_settings_user_id ON user_settings (user_id);

COMMENT ON TABLE user_settings IS 'Per-user preference key-value store';

-- =============================================================================
-- System Settings
-- =============================================================================

CREATE TABLE IF NOT EXISTS system_settings (
    key             TEXT            PRIMARY KEY,
    value           JSONB           DEFAULT '{}',
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

COMMENT ON TABLE system_settings IS 'Global system configuration key-value store';

-- =============================================================================
-- Subscriptions
-- =============================================================================

CREATE TABLE IF NOT EXISTS subscriptions (
    id              BIGSERIAL       PRIMARY KEY,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    team_id         UUID            REFERENCES teams(id) ON DELETE SET NULL,
    plan_name       TEXT            NOT NULL DEFAULT 'free'
                                    CHECK (plan_name IN ('free', 'pro', 'team', 'enterprise')),
    status          TEXT            DEFAULT 'active'
                                    CHECK (status IN ('active', 'cancelled', 'past_due', 'trialing', 'paused')),
    billing_cycle   TEXT            DEFAULT 'monthly'
                                    CHECK (billing_cycle IN ('monthly', 'yearly', 'lifetime')),
    payment_method  TEXT            DEFAULT '',
    auto_renew      BOOLEAN         DEFAULT true,
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON subscriptions (user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_team_id ON subscriptions (team_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status  ON subscriptions (status);

COMMENT ON TABLE subscriptions IS 'User and team billing subscriptions';

-- =============================================================================
-- User Integrations
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_integrations (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider        TEXT            NOT NULL DEFAULT '',
    webhook_url     TEXT            DEFAULT '',
    channel_id      TEXT            DEFAULT '',
    guild_id        TEXT            DEFAULT '',
    team_id         TEXT            DEFAULT '',
    enabled         BOOLEAN         DEFAULT true,
    metadata        JSONB           DEFAULT '{}',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_integrations_user_id  ON user_integrations (user_id);
CREATE INDEX IF NOT EXISTS idx_user_integrations_provider ON user_integrations (provider);

COMMENT ON TABLE user_integrations IS 'Third-party service integrations (Slack, Discord, etc.)';

-- =============================================================================
-- Push Subscriptions (Web Push)
-- =============================================================================

CREATE TABLE IF NOT EXISTS push_subscriptions (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    endpoint        TEXT            NOT NULL,
    p256dh          TEXT            NOT NULL DEFAULT '',
    auth            TEXT            NOT NULL DEFAULT '',
    user_agent      TEXT            DEFAULT '',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_id ON push_subscriptions (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_push_subscriptions_endpoint
    ON push_subscriptions (endpoint);

COMMENT ON TABLE push_subscriptions IS 'Web Push API subscription records';
