-- =============================================================================
-- 019_create_audit_trail.sql
-- =============================================================================
-- Uses supa_audit (if available) for row-level change tracking and
-- pgAudit for query-level audit logging.
-- If extensions are not available, this migration is a no-op.
-- =============================================================================

-- ── 1. Try to enable extensions ──

DO $$ BEGIN
    CREATE EXTENSION IF NOT EXISTS supa_audit CASCADE;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'supa_audit not available — audit tracking will be skipped: %', SQLERRM;
END $$;

DO $$ BEGIN
    CREATE EXTENSION IF NOT EXISTS pgaudit;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pgaudit not available — query audit logging will be skipped: %', SQLERRM;
END $$;

-- ── 2. Configure pgAudit (only if installed) ──

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgaudit') THEN
        ALTER SYSTEM SET pgaudit.log = 'ddl, role, write';
        ALTER SYSTEM SET pgaudit.log_catalog = 'off';
        ALTER SYSTEM SET pgaudit.log_client = 'on';
        ALTER SYSTEM SET pgaudit.log_level = 'log';
        ALTER SYSTEM SET pgaudit.log_parameter = 'off';
        ALTER SYSTEM SET pgaudit.log_relation = 'on';
        ALTER SYSTEM SET pgaudit.log_statement_once = 'on';
        PERFORM pg_reload_conf();
    END IF;
END $$;

-- ── 3. Enable supa_audit tracking (only if installed) ──

DO $audit_block$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'supa_audit') THEN
        RAISE NOTICE 'supa_audit not installed — skipping audit tracking setup';
        RETURN;
    END IF;

    -- Users
    PERFORM audit.enable_tracking('public.users'::regclass);
    PERFORM audit.enable_tracking('public.passkeys'::regclass);
    PERFORM audit.enable_tracking('public.oauth_accounts'::regclass);
    PERFORM audit.enable_tracking('public.device_tokens'::regclass);
    PERFORM audit.enable_tracking('public.otp_codes'::regclass);
    PERFORM audit.enable_tracking('public.magic_link_tokens'::regclass);
    PERFORM audit.enable_tracking('public.verification_types'::regclass);
    PERFORM audit.enable_tracking('public.user_verifications'::regclass);

    -- Teams
    PERFORM audit.enable_tracking('public.teams'::regclass);
    PERFORM audit.enable_tracking('public.memberships'::regclass);

    -- Projects
    PERFORM audit.enable_tracking('public.workspaces'::regclass);
    PERFORM audit.enable_tracking('public.workspace_teams'::regclass);
    PERFORM audit.enable_tracking('public.projects'::regclass);

    -- Features
    PERFORM audit.enable_tracking('public.features'::regclass);
    PERFORM audit.enable_tracking('public.plans'::regclass);
    PERFORM audit.enable_tracking('public.requests'::regclass);
    PERFORM audit.enable_tracking('public.epics'::regclass);
    PERFORM audit.enable_tracking('public.stories'::regclass);
    PERFORM audit.enable_tracking('public.tasks'::regclass);

    -- Notes
    PERFORM audit.enable_tracking('public.notes'::regclass);
    PERFORM audit.enable_tracking('public.note_revisions'::regclass);
    PERFORM audit.enable_tracking('public.docs'::regclass);

    -- Agents
    PERFORM audit.enable_tracking('public.agents'::regclass);
    PERFORM audit.enable_tracking('public.skills'::regclass);
    PERFORM audit.enable_tracking('public.workflows'::regclass);
    PERFORM audit.enable_tracking('public.project_skills'::regclass);
    PERFORM audit.enable_tracking('public.project_agents'::regclass);

    -- Health
    PERFORM audit.enable_tracking('public.health_profiles'::regclass);
    PERFORM audit.enable_tracking('public.water_logs'::regclass);
    PERFORM audit.enable_tracking('public.meal_logs'::regclass);
    PERFORM audit.enable_tracking('public.caffeine_logs'::regclass);
    PERFORM audit.enable_tracking('public.pomodoro_sessions'::regclass);
    PERFORM audit.enable_tracking('public.sleep_configs'::regclass);
    PERFORM audit.enable_tracking('public.sleep_logs'::regclass);
    PERFORM audit.enable_tracking('public.health_snapshots'::regclass);

    -- Sessions
    PERFORM audit.enable_tracking('public.ai_sessions'::regclass);
    PERFORM audit.enable_tracking('public.session_turns'::regclass);
    PERFORM audit.enable_tracking('public.persons'::regclass);
    PERFORM audit.enable_tracking('public.delegations'::regclass);
    PERFORM audit.enable_tracking('public.assignment_rules'::regclass);

    -- Settings
    PERFORM audit.enable_tracking('public.user_settings'::regclass);
    PERFORM audit.enable_tracking('public.system_settings'::regclass);
    PERFORM audit.enable_tracking('public.subscriptions'::regclass);
    PERFORM audit.enable_tracking('public.user_integrations'::regclass);
    PERFORM audit.enable_tracking('public.push_subscriptions'::regclass);

    -- API Collections
    PERFORM audit.enable_tracking('public.api_collections'::regclass);
    PERFORM audit.enable_tracking('public.api_endpoints'::regclass);
    PERFORM audit.enable_tracking('public.api_environments'::regclass);

    -- Presentations
    PERFORM audit.enable_tracking('public.presentations'::regclass);
    PERFORM audit.enable_tracking('public.presentation_slides'::regclass);

    -- Community
    PERFORM audit.enable_tracking('public.community_posts'::regclass);
    PERFORM audit.enable_tracking('public.community_likes'::regclass);
    PERFORM audit.enable_tracking('public.comments'::regclass);
    PERFORM audit.enable_tracking('public.issues'::regclass);
    PERFORM audit.enable_tracking('public.sponsors'::regclass);
    PERFORM audit.enable_tracking('public.contact_messages'::regclass);
    PERFORM audit.enable_tracking('public.pages'::regclass);
    PERFORM audit.enable_tracking('public.posts'::regclass);

    -- Admin
    PERFORM audit.enable_tracking('public.badge_definitions'::regclass);
    PERFORM audit.enable_tracking('public.user_badges'::regclass);
    PERFORM audit.enable_tracking('public.user_wallets'::regclass);
    PERFORM audit.enable_tracking('public.points_transactions'::regclass);
    PERFORM audit.enable_tracking('public.github_repos'::regclass);
    PERFORM audit.enable_tracking('public.github_issues'::regclass);

    -- Tunnels & Sharing
    PERFORM audit.enable_tracking('public.tunnels'::regclass);
    PERFORM audit.enable_tracking('public.shared_contents'::regclass);
    PERFORM audit.enable_tracking('public.share_comments'::regclass);
    PERFORM audit.enable_tracking('public.team_shares'::regclass);
    PERFORM audit.enable_tracking('public.content_views'::regclass);
    PERFORM audit.enable_tracking('public.custom_domains'::regclass);
    PERFORM audit.enable_tracking('public.action_histories'::regclass);
    PERFORM audit.enable_tracking('public.action_logs'::regclass);
    PERFORM audit.enable_tracking('public.mcp_event_logs'::regclass);
    PERFORM audit.enable_tracking('public.sync_logs'::regclass);
    PERFORM audit.enable_tracking('public.conflict_logs'::regclass);
    PERFORM audit.enable_tracking('public.repo_workspaces'::regclass);
    PERFORM audit.enable_tracking('public.notifications'::regclass);
    PERFORM audit.enable_tracking('public.packs'::regclass);

    -- Feature Flags
    PERFORM audit.enable_tracking('public.feature_flags'::regclass);
    PERFORM audit.enable_tracking('public.feature_flag_overrides'::regclass);
    PERFORM audit.enable_tracking('public.experiments'::regclass);
    PERFORM audit.enable_tracking('public.experiment_assignments'::regclass);

    -- RLS on audit table
    ALTER TABLE audit.record_version ENABLE ROW LEVEL SECURITY;

    CREATE POLICY IF NOT EXISTS audit_service_all ON audit.record_version
        FOR SELECT
        USING (current_setting('request.jwt.claims', true)::jsonb ->> 'role' = 'service_role');

    CREATE POLICY IF NOT EXISTS audit_admin_read ON audit.record_version
        FOR SELECT
        USING (
            EXISTS (
                SELECT 1 FROM users
                WHERE auth_uid = auth.uid() AND role = 'admin'
            )
        );

    -- Views
    CREATE OR REPLACE VIEW audit.recent_changes AS
    SELECT rv.id, rv.op, rv.table_schema, rv.table_name, rv.record_id, rv.ts, rv.record, rv.old_record
    FROM audit.record_version rv
    WHERE rv.ts >= NOW() - INTERVAL '24 hours'
    ORDER BY rv.ts DESC;

    CREATE OR REPLACE VIEW audit.daily_summary AS
    SELECT date_trunc('day', ts) AS day, table_name, op, count(*) AS change_count
    FROM audit.record_version
    WHERE ts >= NOW() - INTERVAL '30 days'
    GROUP BY 1, 2, 3
    ORDER BY 1 DESC, 4 DESC;

    -- Cleanup function
    CREATE OR REPLACE FUNCTION audit.cleanup_old_entries(p_older_than INTERVAL DEFAULT '90 days')
    RETURNS BIGINT AS $$
    DECLARE v_count BIGINT;
    BEGIN
        DELETE FROM audit.record_version WHERE ts < NOW() - p_older_than;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        RETURN v_count;
    END;
    $$ LANGUAGE plpgsql;

END
$audit_block$;
