-- 021_enhance_teams_subscriptions.sql
-- Enhance teams as tenants, add subscription plans, usage tracking, invoices,
-- team invitations, and payment gateway support (GitHub Sponsors + Buy Me a Coffee).
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- 1. Enhance Teams with Tenant Columns
-- =============================================================================

ALTER TABLE teams ADD COLUMN IF NOT EXISTS settings         JSONB       DEFAULT '{}';
ALTER TABLE teams ADD COLUMN IF NOT EXISTS billing_email    TEXT        DEFAULT '';
ALTER TABLE teams ADD COLUMN IF NOT EXISTS is_personal      BOOLEAN     DEFAULT false;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS max_members      INTEGER     DEFAULT 5;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS storage_limit_mb INTEGER     DEFAULT 500;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS status           TEXT        DEFAULT 'active';

-- Add CHECK constraint for team status (idempotent via IF NOT EXISTS name)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_teams_status'
    ) THEN
        ALTER TABLE teams ADD CONSTRAINT chk_teams_status
            CHECK (status IN ('active', 'suspended', 'archived'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_teams_status      ON teams (status);
CREATE INDEX IF NOT EXISTS idx_teams_is_personal ON teams (is_personal);

-- =============================================================================
-- 2. Subscription Plans (Predefined Tiers)
-- =============================================================================

CREATE TABLE IF NOT EXISTS subscription_plans (
    id                  TEXT            PRIMARY KEY,
    name                TEXT            NOT NULL,
    description         TEXT            DEFAULT '',
    price_monthly       INTEGER         DEFAULT 0,
    price_yearly        INTEGER         DEFAULT 0,
    max_members         INTEGER         DEFAULT 1,
    max_projects        INTEGER         DEFAULT 3,
    max_features        INTEGER         DEFAULT 50,
    max_tunnels         INTEGER         DEFAULT 1,
    max_storage_mb      INTEGER         DEFAULT 500,
    max_ai_sessions     INTEGER         DEFAULT 100,
    custom_domain       BOOLEAN         DEFAULT false,
    priority_support    BOOLEAN         DEFAULT false,
    api_rate_limit      INTEGER         DEFAULT 100,
    features            JSONB           DEFAULT '[]',
    is_active           BOOLEAN         DEFAULT true,
    sort_order          INTEGER         DEFAULT 0,
    created_at          TIMESTAMPTZ     DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     DEFAULT NOW()
);

COMMENT ON TABLE subscription_plans IS 'Predefined subscription plan tiers with resource limits and pricing';
COMMENT ON COLUMN subscription_plans.price_monthly IS 'Monthly price in cents (USD)';
COMMENT ON COLUMN subscription_plans.price_yearly IS 'Yearly price in cents (USD)';
COMMENT ON COLUMN subscription_plans.api_rate_limit IS 'Maximum API requests per minute';
COMMENT ON COLUMN subscription_plans.features IS 'JSON array of feature slugs included in this plan';

-- Seed the four plan tiers (upsert to be idempotent)
INSERT INTO subscription_plans (id, name, description, price_monthly, price_yearly,
    max_members, max_projects, max_features, max_tunnels, max_storage_mb,
    max_ai_sessions, custom_domain, priority_support, api_rate_limit, features,
    is_active, sort_order)
VALUES
    ('free', 'Free', 'Get started with Orchestra for free',
        0, 0,
        1, 3, 50, 1, 500,
        100, false, false, 100,
        '["basic_features", "community_support"]',
        true, 0),
    ('pro', 'Pro', 'For professionals who need more power',
        900, 9000,
        1, 10, -1, 3, 5120,
        1000, true, false, 500,
        '["basic_features", "custom_domain", "advanced_analytics", "priority_queue"]',
        true, 1),
    ('team', 'Team', 'Collaborate with your team',
        2500, 25000,
        10, 25, -1, 10, 20480,
        5000, true, true, 1000,
        '["basic_features", "custom_domain", "advanced_analytics", "priority_queue", "priority_support", "team_management", "shared_tunnels"]',
        true, 2),
    ('enterprise', 'Enterprise', 'For organizations that need the best',
        9900, 99000,
        100, -1, -1, 50, 102400,
        -1, true, true, 5000,
        '["basic_features", "custom_domain", "advanced_analytics", "priority_queue", "priority_support", "team_management", "shared_tunnels", "sso", "audit_logs", "dedicated_support"]',
        true, 3)
ON CONFLICT (id) DO UPDATE SET
    name            = EXCLUDED.name,
    description     = EXCLUDED.description,
    price_monthly   = EXCLUDED.price_monthly,
    price_yearly    = EXCLUDED.price_yearly,
    max_members     = EXCLUDED.max_members,
    max_projects    = EXCLUDED.max_projects,
    max_features    = EXCLUDED.max_features,
    max_tunnels     = EXCLUDED.max_tunnels,
    max_storage_mb  = EXCLUDED.max_storage_mb,
    max_ai_sessions = EXCLUDED.max_ai_sessions,
    custom_domain   = EXCLUDED.custom_domain,
    priority_support= EXCLUDED.priority_support,
    api_rate_limit  = EXCLUDED.api_rate_limit,
    features        = EXCLUDED.features,
    is_active       = EXCLUDED.is_active,
    sort_order      = EXCLUDED.sort_order,
    updated_at      = NOW();

-- =============================================================================
-- 3. Enhance Subscriptions Table
-- =============================================================================

ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS plan_id                  TEXT        REFERENCES subscription_plans(id);
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS external_id              TEXT        DEFAULT '';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS gateway                  TEXT        DEFAULT 'github_sponsors';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS gateway_customer_id      TEXT        DEFAULT '';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS gateway_subscription_id  TEXT        DEFAULT '';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS trial_ends_at            TIMESTAMPTZ;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS cancelled_at             TIMESTAMPTZ;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS current_period_start     TIMESTAMPTZ;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS current_period_end       TIMESTAMPTZ;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS metadata                 JSONB       DEFAULT '{}';

-- Add CHECK constraint for gateway (idempotent)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_subscriptions_gateway'
    ) THEN
        ALTER TABLE subscriptions ADD CONSTRAINT chk_subscriptions_gateway
            CHECK (gateway IN ('github_sponsors', 'buymeacoffee', 'manual'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_subscriptions_plan_id    ON subscriptions (plan_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_gateway    ON subscriptions (gateway);
CREATE INDEX IF NOT EXISTS idx_subscriptions_external_id ON subscriptions (external_id) WHERE external_id != '';

-- Backfill plan_id from existing plan_name where plan_id is NULL
UPDATE subscriptions
SET plan_id = plan_name
WHERE plan_id IS NULL
  AND plan_name IN ('free', 'pro', 'team', 'enterprise');

-- =============================================================================
-- 4. Payment Events (Webhook Event Log)
-- =============================================================================

CREATE TABLE IF NOT EXISTS payment_events (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id     BIGINT          REFERENCES subscriptions(id) ON DELETE SET NULL,
    gateway             TEXT            NOT NULL
                                        CHECK (gateway IN ('github_sponsors', 'buymeacoffee', 'manual')),
    event_type          TEXT            NOT NULL,
    event_id            TEXT            DEFAULT '',
    payload             JSONB           DEFAULT '{}',
    processed           BOOLEAN         DEFAULT false,
    processed_at        TIMESTAMPTZ,
    error               TEXT            DEFAULT '',
    created_at          TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_events_subscription_id ON payment_events (subscription_id);
CREATE INDEX IF NOT EXISTS idx_payment_events_gateway         ON payment_events (gateway);
CREATE INDEX IF NOT EXISTS idx_payment_events_event_type      ON payment_events (event_type);
CREATE INDEX IF NOT EXISTS idx_payment_events_event_id        ON payment_events (event_id) WHERE event_id != '';
CREATE INDEX IF NOT EXISTS idx_payment_events_processed       ON payment_events (processed) WHERE processed = false;
CREATE INDEX IF NOT EXISTS idx_payment_events_created_at      ON payment_events (created_at);

COMMENT ON TABLE payment_events IS 'Idempotent webhook event log from payment gateways (GitHub Sponsors, Buy Me a Coffee)';
COMMENT ON COLUMN payment_events.event_type IS 'Gateway event type, e.g. sponsorship.created, sponsorship.cancelled, payment.succeeded';
COMMENT ON COLUMN payment_events.event_id IS 'Idempotency key from the gateway to prevent duplicate processing';
COMMENT ON COLUMN payment_events.payload IS 'Raw JSON payload from the webhook';

-- =============================================================================
-- 5. Usage Records (Per-Team/User Resource Tracking)
-- =============================================================================

CREATE TABLE IF NOT EXISTS usage_records (
    id                  BIGSERIAL       PRIMARY KEY,
    user_id             BIGINT          REFERENCES users(id) ON DELETE CASCADE,
    team_id             UUID            REFERENCES teams(id) ON DELETE CASCADE,
    resource_type       TEXT            NOT NULL
                                        CHECK (resource_type IN (
                                            'projects', 'features', 'tunnels', 'storage_mb',
                                            'ai_sessions', 'api_requests', 'members'
                                        )),
    period_start        DATE            NOT NULL,
    period_end          DATE            NOT NULL,
    count               INTEGER         DEFAULT 0,
    limit_value         INTEGER         DEFAULT 0,
    created_at          TIMESTAMPTZ     DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     DEFAULT NOW()
);

-- Composite unique constraint for upsert support
CREATE UNIQUE INDEX IF NOT EXISTS idx_usage_records_unique
    ON usage_records (user_id, team_id, resource_type, period_start);

CREATE INDEX IF NOT EXISTS idx_usage_records_user_id        ON usage_records (user_id);
CREATE INDEX IF NOT EXISTS idx_usage_records_team_id        ON usage_records (team_id);
CREATE INDEX IF NOT EXISTS idx_usage_records_resource_type  ON usage_records (resource_type);
CREATE INDEX IF NOT EXISTS idx_usage_records_period         ON usage_records (period_start, period_end);

COMMENT ON TABLE usage_records IS 'Per-period resource usage counters for enforcing subscription plan limits';
COMMENT ON COLUMN usage_records.resource_type IS 'One of: projects, features, tunnels, storage_mb, ai_sessions, api_requests, members';
COMMENT ON COLUMN usage_records.count IS 'Current usage count for the resource in the given period';
COMMENT ON COLUMN usage_records.limit_value IS 'Maximum allowed count based on subscription plan (-1 = unlimited)';

-- =============================================================================
-- 6. Invoices (Billing History)
-- =============================================================================

CREATE TABLE IF NOT EXISTS invoices (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id     BIGINT          NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    user_id             BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    team_id             UUID            REFERENCES teams(id) ON DELETE SET NULL,
    amount              INTEGER         NOT NULL DEFAULT 0,
    currency            TEXT            DEFAULT 'USD',
    status              TEXT            DEFAULT 'pending'
                                        CHECK (status IN ('pending', 'paid', 'failed', 'refunded', 'cancelled')),
    gateway             TEXT            NOT NULL
                                        CHECK (gateway IN ('github_sponsors', 'buymeacoffee', 'manual')),
    gateway_invoice_id  TEXT            DEFAULT '',
    period_start        DATE,
    period_end          DATE,
    paid_at             TIMESTAMPTZ,
    metadata            JSONB           DEFAULT '{}',
    created_at          TIMESTAMPTZ     DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_invoices_subscription_id     ON invoices (subscription_id);
CREATE INDEX IF NOT EXISTS idx_invoices_user_id             ON invoices (user_id);
CREATE INDEX IF NOT EXISTS idx_invoices_team_id             ON invoices (team_id);
CREATE INDEX IF NOT EXISTS idx_invoices_status              ON invoices (status);
CREATE INDEX IF NOT EXISTS idx_invoices_gateway             ON invoices (gateway);
CREATE INDEX IF NOT EXISTS idx_invoices_gateway_invoice_id  ON invoices (gateway_invoice_id) WHERE gateway_invoice_id != '';
CREATE INDEX IF NOT EXISTS idx_invoices_period              ON invoices (period_start, period_end);

COMMENT ON TABLE invoices IS 'Billing history for subscription payments across all gateways';
COMMENT ON COLUMN invoices.amount IS 'Invoice amount in cents (USD)';
COMMENT ON COLUMN invoices.status IS 'One of: pending, paid, failed, refunded, cancelled';
COMMENT ON COLUMN invoices.gateway IS 'Payment gateway: github_sponsors, buymeacoffee, or manual';

-- =============================================================================
-- 7. Team Invitations
-- =============================================================================

CREATE TABLE IF NOT EXISTS team_invitations (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id             UUID            NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    invited_by          BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    email               TEXT            NOT NULL,
    role                TEXT            DEFAULT 'member'
                                        CHECK (role IN ('admin', 'manager', 'member', 'viewer')),
    token               TEXT            UNIQUE NOT NULL,
    status              TEXT            DEFAULT 'pending'
                                        CHECK (status IN ('pending', 'accepted', 'expired', 'revoked')),
    expires_at          TIMESTAMPTZ     NOT NULL,
    accepted_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_team_invitations_team_id     ON team_invitations (team_id);
CREATE INDEX IF NOT EXISTS idx_team_invitations_invited_by  ON team_invitations (invited_by);
CREATE INDEX IF NOT EXISTS idx_team_invitations_email       ON team_invitations (email);
CREATE INDEX IF NOT EXISTS idx_team_invitations_token       ON team_invitations (token);
CREATE INDEX IF NOT EXISTS idx_team_invitations_status      ON team_invitations (status);
CREATE INDEX IF NOT EXISTS idx_team_invitations_expires_at  ON team_invitations (expires_at);

COMMENT ON TABLE team_invitations IS 'Pending team invitations with token-based acceptance';
COMMENT ON COLUMN team_invitations.role IS 'Role to assign on acceptance: admin, manager, member, or viewer';
COMMENT ON COLUMN team_invitations.token IS 'Unique token sent via email for invitation acceptance';
COMMENT ON COLUMN team_invitations.status IS 'One of: pending, accepted, expired, revoked';

-- =============================================================================
-- 8. Enable Audit Tracking on New Tables
-- =============================================================================

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'supa_audit') THEN
        PERFORM audit.enable_tracking('public.subscription_plans'::regclass);
        PERFORM audit.enable_tracking('public.payment_events'::regclass);
        PERFORM audit.enable_tracking('public.usage_records'::regclass);
        PERFORM audit.enable_tracking('public.invoices'::regclass);
        PERFORM audit.enable_tracking('public.team_invitations'::regclass);
    END IF;
END $$;

-- =============================================================================
-- 9. Updated-at Trigger Function (reuse if exists)
-- =============================================================================

CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at triggers to new tables that have updated_at columns

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_subscription_plans'
    ) THEN
        CREATE TRIGGER set_updated_at_subscription_plans
            BEFORE UPDATE ON subscription_plans
            FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_usage_records'
    ) THEN
        CREATE TRIGGER set_updated_at_usage_records
            BEFORE UPDATE ON usage_records
            FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_invoices'
    ) THEN
        CREATE TRIGGER set_updated_at_invoices
            BEFORE UPDATE ON invoices
            FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
    END IF;
END $$;

-- =============================================================================
-- 10. Row-Level Security Policies
-- =============================================================================

-- Subscription Plans: readable by everyone, writable by admins only
ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS subscription_plans_select ON subscription_plans
    FOR SELECT USING (true);

CREATE POLICY IF NOT EXISTS subscription_plans_admin ON subscription_plans
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users
            WHERE auth_uid = auth.uid() AND role = 'admin'
        )
    );

-- Payment Events: only service role and admins
ALTER TABLE payment_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS payment_events_service ON payment_events
    FOR ALL USING (
        current_setting('request.jwt.claims', true)::jsonb ->> 'role' = 'service_role'
    );

CREATE POLICY IF NOT EXISTS payment_events_admin ON payment_events
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users
            WHERE auth_uid = auth.uid() AND role = 'admin'
        )
    );

-- Usage Records: users see their own, team owners/admins see team records
ALTER TABLE usage_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS usage_records_own ON usage_records
    FOR SELECT USING (
        user_id = (SELECT id FROM users WHERE auth_uid = auth.uid())
    );

CREATE POLICY IF NOT EXISTS usage_records_team ON usage_records
    FOR SELECT USING (
        team_id IN (
            SELECT m.team_id FROM memberships m
            JOIN users u ON u.id = m.user_id
            WHERE u.auth_uid = auth.uid()
              AND m.role IN ('owner', 'admin')
        )
    );

CREATE POLICY IF NOT EXISTS usage_records_service ON usage_records
    FOR ALL USING (
        current_setting('request.jwt.claims', true)::jsonb ->> 'role' = 'service_role'
    );

-- Invoices: users see their own, team owners/admins see team invoices
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS invoices_own ON invoices
    FOR SELECT USING (
        user_id = (SELECT id FROM users WHERE auth_uid = auth.uid())
    );

CREATE POLICY IF NOT EXISTS invoices_team ON invoices
    FOR SELECT USING (
        team_id IN (
            SELECT m.team_id FROM memberships m
            JOIN users u ON u.id = m.user_id
            WHERE u.auth_uid = auth.uid()
              AND m.role IN ('owner', 'admin')
        )
    );

CREATE POLICY IF NOT EXISTS invoices_service ON invoices
    FOR ALL USING (
        current_setting('request.jwt.claims', true)::jsonb ->> 'role' = 'service_role'
    );

-- Team Invitations: team admins can manage, invited users can see their own
ALTER TABLE team_invitations ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS team_invitations_team_admin ON team_invitations
    FOR ALL USING (
        team_id IN (
            SELECT m.team_id FROM memberships m
            JOIN users u ON u.id = m.user_id
            WHERE u.auth_uid = auth.uid()
              AND m.role IN ('owner', 'admin')
        )
    );

CREATE POLICY IF NOT EXISTS team_invitations_invitee ON team_invitations
    FOR SELECT USING (
        email = (SELECT email FROM users WHERE auth_uid = auth.uid())
    );

-- =============================================================================
-- Done
-- =============================================================================
