-- 022_enhance_notifications.sql
-- Enhances the notification system with categories, priorities, delivery tracking,
-- user preferences, and reusable templates.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- 1. Enhance existing notifications table
-- =============================================================================

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'system'
    CHECK (category IN ('system', 'feature', 'team', 'billing', 'security', 'social', 'ai', 'tunnel', 'sync'));

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS priority TEXT DEFAULT 'normal'
    CHECK (priority IN ('low', 'normal', 'high', 'urgent'));

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS action_url TEXT DEFAULT '';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS action_label TEXT DEFAULT '';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS entity_type TEXT DEFAULT '';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS entity_id TEXT DEFAULT '';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS icon TEXT DEFAULT '';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS image_url TEXT DEFAULT '';

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS sender_id BIGINT REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS team_id UUID REFERENCES teams(id) ON DELETE CASCADE;

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS data JSONB DEFAULT '{}';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS dismissed_at TIMESTAMPTZ;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS delivery_channels JSONB DEFAULT '["in_app"]';

-- Indexes on the new notification columns
CREATE INDEX IF NOT EXISTS idx_notifications_category
    ON notifications (category);

CREATE INDEX IF NOT EXISTS idx_notifications_priority
    ON notifications (priority);

CREATE INDEX IF NOT EXISTS idx_notifications_entity
    ON notifications (entity_type, entity_id);

CREATE INDEX IF NOT EXISTS idx_notifications_sender_id
    ON notifications (sender_id);

CREATE INDEX IF NOT EXISTS idx_notifications_team_id
    ON notifications (team_id);

CREATE INDEX IF NOT EXISTS idx_notifications_dismissed_at
    ON notifications (dismissed_at) WHERE dismissed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_notifications_delivered_at
    ON notifications (delivered_at);

CREATE INDEX IF NOT EXISTS idx_notifications_created_at
    ON notifications (created_at);

COMMENT ON TABLE notifications IS 'In-app and multi-channel user notifications with delivery tracking';

-- =============================================================================
-- 2. Notification Preferences (per-user per-category delivery settings)
-- =============================================================================

CREATE TABLE IF NOT EXISTS notification_preferences (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category        TEXT            NOT NULL
                                    CHECK (category IN ('system', 'feature', 'team', 'billing', 'security', 'social', 'ai', 'tunnel', 'sync')),
    in_app          BOOLEAN         DEFAULT true,
    email           BOOLEAN         DEFAULT false,
    push            BOOLEAN         DEFAULT false,
    discord         BOOLEAN         DEFAULT false,
    slack           BOOLEAN         DEFAULT false,
    mute_until      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    UNIQUE (user_id, category)
);

CREATE INDEX IF NOT EXISTS idx_notification_preferences_user_id
    ON notification_preferences (user_id);

CREATE INDEX IF NOT EXISTS idx_notification_preferences_category
    ON notification_preferences (category);

COMMENT ON TABLE notification_preferences IS 'Per-user per-category notification delivery channel settings';

-- =============================================================================
-- 3. Notification Templates (reusable notification blueprints)
-- =============================================================================

CREATE TABLE IF NOT EXISTS notification_templates (
    id                  TEXT        PRIMARY KEY,
    category            TEXT        NOT NULL
                                    CHECK (category IN ('system', 'feature', 'team', 'billing', 'security', 'social', 'ai', 'tunnel', 'sync')),
    title_template      TEXT        NOT NULL DEFAULT '',
    message_template    TEXT        NOT NULL DEFAULT '',
    default_channels    JSONB       DEFAULT '["in_app"]',
    default_priority    TEXT        DEFAULT 'normal'
                                    CHECK (default_priority IN ('low', 'normal', 'high', 'urgent')),
    icon                TEXT        DEFAULT '',
    is_active           BOOLEAN     DEFAULT true,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_templates_category
    ON notification_templates (category);

CREATE INDEX IF NOT EXISTS idx_notification_templates_is_active
    ON notification_templates (is_active) WHERE is_active = true;

COMMENT ON TABLE notification_templates IS 'Reusable notification templates with {{variable}} interpolation support';

-- Seed default templates
INSERT INTO notification_templates (id, category, title_template, message_template, default_priority, icon)
VALUES
    ('feature.assigned',          'feature',  'Feature Assigned',     '{{feature_name}} has been assigned to you',                                'normal',  'assignment'),
    ('feature.status_changed',    'feature',  'Feature Updated',      '{{feature_name}} moved to {{status}}',                                    'normal',  'update'),
    ('feature.review_requested',  'feature',  'Review Requested',     '{{requester}} requested your review on {{feature_name}}',                  'high',    'review'),
    ('team.invited',              'team',     'Team Invitation',      '{{inviter}} invited you to join {{team_name}}',                            'high',    'invite'),
    ('team.member_joined',        'team',     'New Team Member',      '{{member_name}} joined {{team_name}}',                                    'normal',  'person_add'),
    ('team.member_left',          'team',     'Member Left',          '{{member_name}} left {{team_name}}',                                      'normal',  'person_remove'),
    ('billing.payment_succeeded', 'billing',  'Payment Successful',   'Your {{plan_name}} subscription payment of {{amount}} was processed',     'normal',  'payment'),
    ('billing.payment_failed',    'billing',  'Payment Failed',       'We couldn''t process your payment for {{plan_name}}',                     'urgent',  'payment_error'),
    ('billing.trial_ending',      'billing',  'Trial Ending',         'Your {{plan_name}} trial ends in {{days}} days',                          'high',    'timer'),
    ('security.new_login',        'security', 'New Login Detected',   'New sign-in from {{device}} in {{location}}',                             'high',    'security'),
    ('security.password_changed', 'security', 'Password Changed',     'Your password was changed successfully',                                  'normal',  'lock'),
    ('tunnel.connected',          'tunnel',   'Tunnel Connected',     '{{tunnel_name}} is now online',                                           'normal',  'cloud_done'),
    ('tunnel.disconnected',       'tunnel',   'Tunnel Offline',       '{{tunnel_name}} went offline',                                            'high',    'cloud_off'),
    ('ai.session_complete',       'ai',       'Session Complete',     'AI session completed: {{summary}}',                                       'normal',  'smart_toy'),
    ('social.new_follower',       'social',   'New Follower',         '{{follower_name}} started following you',                                 'normal',  'person'),
    ('social.post_liked',         'social',   'Post Liked',           '{{liker_name}} liked your post',                                          'low',     'thumb_up'),
    ('social.comment_received',   'social',   'New Comment',          '{{commenter_name}} commented on {{entity_name}}',                         'normal',  'comment'),
    ('sync.conflict',             'sync',     'Sync Conflict',        'Conflict detected in {{entity_type}} {{entity_name}}',                    'high',    'sync_problem')
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 4. Notification Deliveries (per-channel delivery tracking)
-- =============================================================================

CREATE TABLE IF NOT EXISTS notification_deliveries (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id     BIGINT      NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    channel             TEXT        NOT NULL
                                    CHECK (channel IN ('in_app', 'email', 'push', 'discord', 'slack')),
    status              TEXT        DEFAULT 'pending'
                                    CHECK (status IN ('pending', 'sent', 'delivered', 'failed', 'bounced')),
    provider_id         TEXT        DEFAULT '',
    error               TEXT        DEFAULT '',
    sent_at             TIMESTAMPTZ,
    delivered_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_notification_id
    ON notification_deliveries (notification_id);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_channel
    ON notification_deliveries (channel);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_status
    ON notification_deliveries (status);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_sent_at
    ON notification_deliveries (sent_at);

COMMENT ON TABLE notification_deliveries IS 'Per-channel delivery tracking for each notification';

-- =============================================================================
-- 5. Enhance existing push_subscriptions table
-- =============================================================================

ALTER TABLE push_subscriptions ADD COLUMN IF NOT EXISTS platform TEXT DEFAULT 'web'
    CHECK (platform IN ('web', 'ios', 'android', 'macos', 'windows', 'linux'));

ALTER TABLE push_subscriptions ADD COLUMN IF NOT EXISTS device_name TEXT DEFAULT '';
ALTER TABLE push_subscriptions ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
ALTER TABLE push_subscriptions ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMPTZ;
ALTER TABLE push_subscriptions ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_platform
    ON push_subscriptions (platform);

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_is_active
    ON push_subscriptions (is_active) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_deleted_at
    ON push_subscriptions (deleted_at);

COMMENT ON TABLE push_subscriptions IS 'Multi-platform push notification subscription records';

-- =============================================================================
-- 6. Enable audit tracking on new tables
-- =============================================================================

SELECT audit.enable_tracking('public.notification_preferences'::regclass);
SELECT audit.enable_tracking('public.notification_templates'::regclass);
SELECT audit.enable_tracking('public.notification_deliveries'::regclass);

-- =============================================================================
-- 7. updated_at trigger for new tables
-- =============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'trg_notification_preferences_updated_at'
    ) THEN
        CREATE TRIGGER trg_notification_preferences_updated_at
            BEFORE UPDATE ON notification_preferences
            FOR EACH ROW
            EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'trg_notification_templates_updated_at'
    ) THEN
        CREATE TRIGGER trg_notification_templates_updated_at
            BEFORE UPDATE ON notification_templates
            FOR EACH ROW
            EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;
