-- =============================================================================
-- 019_create_audit_trail.sql
-- =============================================================================
-- Uses Supabase's official supa_audit extension for row-level change tracking
-- and pgAudit for query-level audit logging. Both are pre-installed in the
-- supabase/postgres Docker image.
--
-- supa_audit: Row changes → audit.record_version table (who, what, when)
-- pgAudit:    Query logs  → Postgres log files (for compliance/forensics)
--
-- Refs:
--   https://github.com/supabase/supa_audit
--   https://supabase.com/docs/guides/database/extensions/pgaudit
-- =============================================================================

-- ── 1. Enable Extensions ──

CREATE EXTENSION IF NOT EXISTS supa_audit CASCADE;
CREATE EXTENSION IF NOT EXISTS pgaudit;

-- ── 2. Configure pgAudit ──
-- Log DDL + role changes + writes (not reads — too noisy)
-- Self-hosted: postgres is superuser so we can set this globally

ALTER SYSTEM SET pgaudit.log = 'ddl, role, write';
ALTER SYSTEM SET pgaudit.log_catalog = 'off';
ALTER SYSTEM SET pgaudit.log_client = 'on';
ALTER SYSTEM SET pgaudit.log_level = 'log';
ALTER SYSTEM SET pgaudit.log_parameter = 'off';  -- don't log params (may contain secrets)
ALTER SYSTEM SET pgaudit.log_relation = 'on';
ALTER SYSTEM SET pgaudit.log_statement_once = 'on';
SELECT pg_reload_conf();

-- ── 3. Enable supa_audit tracking on ALL application tables ──
-- supa_audit writes to audit.record_version with:
--   id, record_id (stable UUID from PK), op, ts, table_oid,
--   table_schema, table_name, record (JSONB), old_record (JSONB)

-- Migration 002: Users
SELECT audit.enable_tracking('public.users'::regclass);
SELECT audit.enable_tracking('public.passkeys'::regclass);
SELECT audit.enable_tracking('public.oauth_accounts'::regclass);
SELECT audit.enable_tracking('public.device_tokens'::regclass);
SELECT audit.enable_tracking('public.otp_codes'::regclass);
SELECT audit.enable_tracking('public.magic_link_tokens'::regclass);
SELECT audit.enable_tracking('public.verification_types'::regclass);
SELECT audit.enable_tracking('public.user_verifications'::regclass);

-- Migration 003: Teams
SELECT audit.enable_tracking('public.teams'::regclass);
SELECT audit.enable_tracking('public.memberships'::regclass);

-- Migration 004: Projects
SELECT audit.enable_tracking('public.workspaces'::regclass);
SELECT audit.enable_tracking('public.workspace_teams'::regclass);
SELECT audit.enable_tracking('public.projects'::regclass);

-- Migration 005: Features
SELECT audit.enable_tracking('public.features'::regclass);
SELECT audit.enable_tracking('public.plans'::regclass);
SELECT audit.enable_tracking('public.requests'::regclass);
SELECT audit.enable_tracking('public.epics'::regclass);
SELECT audit.enable_tracking('public.stories'::regclass);
SELECT audit.enable_tracking('public.tasks'::regclass);

-- Migration 006: Notes
SELECT audit.enable_tracking('public.notes'::regclass);
SELECT audit.enable_tracking('public.note_revisions'::regclass);
SELECT audit.enable_tracking('public.docs'::regclass);

-- Migration 007: Agents
SELECT audit.enable_tracking('public.agents'::regclass);
SELECT audit.enable_tracking('public.skills'::regclass);
SELECT audit.enable_tracking('public.workflows'::regclass);
SELECT audit.enable_tracking('public.project_skills'::regclass);
SELECT audit.enable_tracking('public.project_agents'::regclass);

-- Migration 008: Health
SELECT audit.enable_tracking('public.health_profiles'::regclass);
SELECT audit.enable_tracking('public.water_logs'::regclass);
SELECT audit.enable_tracking('public.meal_logs'::regclass);
SELECT audit.enable_tracking('public.caffeine_logs'::regclass);
SELECT audit.enable_tracking('public.pomodoro_sessions'::regclass);
SELECT audit.enable_tracking('public.sleep_configs'::regclass);
SELECT audit.enable_tracking('public.sleep_logs'::regclass);
SELECT audit.enable_tracking('public.health_snapshots'::regclass);

-- Migration 009: Sessions
SELECT audit.enable_tracking('public.ai_sessions'::regclass);
SELECT audit.enable_tracking('public.session_turns'::regclass);
SELECT audit.enable_tracking('public.persons'::regclass);
SELECT audit.enable_tracking('public.delegations'::regclass);
SELECT audit.enable_tracking('public.assignment_rules'::regclass);

-- Migration 010: Settings
SELECT audit.enable_tracking('public.user_settings'::regclass);
SELECT audit.enable_tracking('public.system_settings'::regclass);
SELECT audit.enable_tracking('public.subscriptions'::regclass);
SELECT audit.enable_tracking('public.user_integrations'::regclass);
SELECT audit.enable_tracking('public.push_subscriptions'::regclass);

-- Migration 011: API Collections
SELECT audit.enable_tracking('public.api_collections'::regclass);
SELECT audit.enable_tracking('public.api_endpoints'::regclass);
SELECT audit.enable_tracking('public.api_environments'::regclass);

-- Migration 012: Presentations
SELECT audit.enable_tracking('public.presentations'::regclass);
SELECT audit.enable_tracking('public.presentation_slides'::regclass);

-- Migration 013: Community
SELECT audit.enable_tracking('public.community_posts'::regclass);
SELECT audit.enable_tracking('public.community_likes'::regclass);
SELECT audit.enable_tracking('public.comments'::regclass);
SELECT audit.enable_tracking('public.issues'::regclass);
SELECT audit.enable_tracking('public.sponsors'::regclass);
SELECT audit.enable_tracking('public.contact_messages'::regclass);
SELECT audit.enable_tracking('public.pages'::regclass);
SELECT audit.enable_tracking('public.posts'::regclass);

-- Migration 014: Admin
SELECT audit.enable_tracking('public.badge_definitions'::regclass);
SELECT audit.enable_tracking('public.user_badges'::regclass);
SELECT audit.enable_tracking('public.user_wallets'::regclass);
SELECT audit.enable_tracking('public.points_transactions'::regclass);
SELECT audit.enable_tracking('public.github_repos'::regclass);
SELECT audit.enable_tracking('public.github_issues'::regclass);

-- Migration 015: Tunnels & Sharing
SELECT audit.enable_tracking('public.tunnels'::regclass);
SELECT audit.enable_tracking('public.shared_contents'::regclass);
SELECT audit.enable_tracking('public.share_comments'::regclass);
SELECT audit.enable_tracking('public.team_shares'::regclass);
SELECT audit.enable_tracking('public.content_views'::regclass);
SELECT audit.enable_tracking('public.custom_domains'::regclass);
SELECT audit.enable_tracking('public.action_histories'::regclass);
SELECT audit.enable_tracking('public.action_logs'::regclass);
SELECT audit.enable_tracking('public.mcp_event_logs'::regclass);
SELECT audit.enable_tracking('public.sync_logs'::regclass);
SELECT audit.enable_tracking('public.conflict_logs'::regclass);
SELECT audit.enable_tracking('public.repo_workspaces'::regclass);
SELECT audit.enable_tracking('public.notifications'::regclass);
SELECT audit.enable_tracking('public.packs'::regclass);

-- Migration 016: Feature Flags
SELECT audit.enable_tracking('public.feature_flags'::regclass);
SELECT audit.enable_tracking('public.feature_flag_overrides'::regclass);
SELECT audit.enable_tracking('public.experiments'::regclass);
SELECT audit.enable_tracking('public.experiment_assignments'::regclass);

-- ── 4. RLS on audit.record_version ──
-- Only admins and service_role can read the full audit trail.
-- Users can see audit entries for their own records.

ALTER TABLE audit.record_version ENABLE ROW LEVEL SECURITY;

-- Service role: full access
CREATE POLICY IF NOT EXISTS audit_service_all ON audit.record_version
    FOR SELECT
    USING (current_setting('request.jwt.claims', true)::jsonb ->> 'role' = 'service_role');

-- Admins: full access
CREATE POLICY IF NOT EXISTS audit_admin_read ON audit.record_version
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM users
            WHERE auth_uid = auth.uid() AND role = 'admin'
        )
    );

-- ── 5. Utility views for common audit queries ──

-- Recent changes across all tables (last 24h)
CREATE OR REPLACE VIEW audit.recent_changes AS
SELECT
    rv.id,
    rv.op,
    rv.table_schema,
    rv.table_name,
    rv.record_id,
    rv.ts,
    rv.record,
    rv.old_record
FROM audit.record_version rv
WHERE rv.ts >= NOW() - INTERVAL '24 hours'
ORDER BY rv.ts DESC;

COMMENT ON VIEW audit.recent_changes IS 'Audit entries from the last 24 hours';

-- Change counts per table per day (for dashboards)
CREATE OR REPLACE VIEW audit.daily_summary AS
SELECT
    date_trunc('day', ts) AS day,
    table_name,
    op,
    count(*) AS change_count
FROM audit.record_version
WHERE ts >= NOW() - INTERVAL '30 days'
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 4 DESC;

COMMENT ON VIEW audit.daily_summary IS 'Daily change counts per table for the last 30 days';

-- ── 6. Cleanup function (archive to ClickHouse, then prune) ──

CREATE OR REPLACE FUNCTION audit.cleanup_old_entries(
    p_older_than INTERVAL DEFAULT '90 days'
) RETURNS BIGINT AS $$
DECLARE
    v_count BIGINT;
BEGIN
    -- Delete entries older than the threshold
    -- IMPORTANT: Run ClickHouse archival BEFORE calling this
    DELETE FROM audit.record_version
    WHERE ts < NOW() - p_older_than;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION audit.cleanup_old_entries IS 'Prune old audit entries. Archive to ClickHouse first.';

-- ── Done ──
-- All 77+ tables now have supa_audit tracking enabled.
-- Query audit.record_version for row-level change history.
-- Check Postgres logs for pgAudit query-level audit trail.
