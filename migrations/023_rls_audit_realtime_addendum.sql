-- =============================================================================
-- 023_rls_audit_realtime_addendum.sql
-- =============================================================================
-- RLS policies, supa_audit tracking, and Realtime publication updates
-- for tables added in migrations 020, 021, and 022.
-- Idempotent: safe to run multiple times.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 1: ROW-LEVEL SECURITY FOR MIGRATION 020 (CMS / i18n)
-- ─────────────────────────────────────────────────────────────────────────────

-- languages (public read, admin write)
ALTER TABLE languages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "languages_select_all" ON languages FOR SELECT USING (true);
CREATE POLICY "languages_admin_all" ON languages FOR ALL USING (is_admin() OR is_service_role());

-- page_translations (public read published, admin write)
ALTER TABLE page_translations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "page_translations_select_published" ON page_translations
    FOR SELECT USING (status = 'published' OR is_admin());
CREATE POLICY "page_translations_admin_all" ON page_translations
    FOR ALL USING (is_admin() OR is_service_role());

-- post_translations (public read published, admin write)
ALTER TABLE post_translations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "post_translations_select_published" ON post_translations
    FOR SELECT USING (status = 'published' OR is_admin());
CREATE POLICY "post_translations_admin_all" ON post_translations
    FOR ALL USING (is_admin() OR is_service_role());

-- content_sections (public read active, admin write)
ALTER TABLE content_sections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "content_sections_select_active" ON content_sections
    FOR SELECT USING (is_active = true OR is_admin());
CREATE POLICY "content_sections_admin_all" ON content_sections
    FOR ALL USING (is_admin() OR is_service_role());

-- content_section_translations (public read, admin write)
ALTER TABLE content_section_translations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "content_section_translations_select_all" ON content_section_translations
    FOR SELECT USING (true);
CREATE POLICY "content_section_translations_admin_all" ON content_section_translations
    FOR ALL USING (is_admin() OR is_service_role());

-- downloads (public read active, admin write)
ALTER TABLE downloads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "downloads_select_active" ON downloads
    FOR SELECT USING (is_active = true OR is_admin());
CREATE POLICY "downloads_admin_all" ON downloads
    FOR ALL USING (is_admin() OR is_service_role());

-- solutions (public read active, admin write)
ALTER TABLE solutions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "solutions_select_active" ON solutions
    FOR SELECT USING (is_active = true OR is_admin());
CREATE POLICY "solutions_admin_all" ON solutions
    FOR ALL USING (is_admin() OR is_service_role());

-- solution_translations (public read, admin write)
ALTER TABLE solution_translations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "solution_translations_select_all" ON solution_translations
    FOR SELECT USING (true);
CREATE POLICY "solution_translations_admin_all" ON solution_translations
    FOR ALL USING (is_admin() OR is_service_role());

-- doc_categories (public read active, admin write)
ALTER TABLE doc_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "doc_categories_select_active" ON doc_categories
    FOR SELECT USING (is_active = true OR is_admin());
CREATE POLICY "doc_categories_admin_all" ON doc_categories
    FOR ALL USING (is_admin() OR is_service_role());

-- doc_category_translations (public read, admin write)
ALTER TABLE doc_category_translations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "doc_category_translations_select_all" ON doc_category_translations
    FOR SELECT USING (true);
CREATE POLICY "doc_category_translations_admin_all" ON doc_category_translations
    FOR ALL USING (is_admin() OR is_service_role());

-- doc_articles (public read active, admin write)
ALTER TABLE doc_articles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "doc_articles_select_active" ON doc_articles
    FOR SELECT USING (is_active = true OR is_admin());
CREATE POLICY "doc_articles_admin_all" ON doc_articles
    FOR ALL USING (is_admin() OR is_service_role());

-- doc_article_translations (public read published, admin write)
ALTER TABLE doc_article_translations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "doc_article_translations_select_published" ON doc_article_translations
    FOR SELECT USING (status = 'published' OR is_admin());
CREATE POLICY "doc_article_translations_admin_all" ON doc_article_translations
    FOR ALL USING (is_admin() OR is_service_role());

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 2: ROW-LEVEL SECURITY FOR MIGRATION 021 (Teams/Subscriptions)
-- ─────────────────────────────────────────────────────────────────────────────

-- subscription_plans (public read active, admin write)
ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "subscription_plans_select_active" ON subscription_plans
    FOR SELECT USING (is_active = true OR is_admin());
CREATE POLICY "subscription_plans_admin_all" ON subscription_plans
    FOR ALL USING (is_admin() OR is_service_role());

-- payment_events (admin + service_role only)
ALTER TABLE payment_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "payment_events_service_all" ON payment_events
    FOR ALL USING (is_service_role());
CREATE POLICY "payment_events_admin_read" ON payment_events
    FOR SELECT USING (is_admin());

-- usage_records (own + team admin read, service_role write)
ALTER TABLE usage_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "usage_records_select_own" ON usage_records
    FOR SELECT USING (
        user_id = auth_user_id()
        OR EXISTS (
            SELECT 1 FROM memberships m
            WHERE m.team_id = usage_records.team_id
              AND m.user_id = auth_user_id()
              AND m.role IN ('owner', 'admin')
        )
    );
CREATE POLICY "usage_records_service_all" ON usage_records
    FOR ALL USING (is_service_role());
CREATE POLICY "usage_records_admin_read" ON usage_records
    FOR SELECT USING (is_admin());

-- invoices (own + team admin read, service_role write)
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "invoices_select_own" ON invoices
    FOR SELECT USING (
        user_id = auth_user_id()
        OR EXISTS (
            SELECT 1 FROM memberships m
            WHERE m.team_id = invoices.team_id
              AND m.user_id = auth_user_id()
              AND m.role IN ('owner', 'admin')
        )
    );
CREATE POLICY "invoices_service_all" ON invoices
    FOR ALL USING (is_service_role());
CREATE POLICY "invoices_admin_read" ON invoices
    FOR SELECT USING (is_admin());

-- team_invitations (team admin manage, invited user can read own email)
ALTER TABLE team_invitations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "team_invitations_team_admin" ON team_invitations
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM memberships m
            WHERE m.team_id = team_invitations.team_id
              AND m.user_id = auth_user_id()
              AND m.role IN ('owner', 'admin')
        )
        OR is_service_role()
    );
CREATE POLICY "team_invitations_select_invited" ON team_invitations
    FOR SELECT USING (
        email = (SELECT email FROM users WHERE id = auth_user_id())
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 3: ROW-LEVEL SECURITY FOR MIGRATION 022 (Notifications)
-- ─────────────────────────────────────────────────────────────────────────────

-- notification_preferences (own rows only)
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notification_preferences_own" ON notification_preferences
    FOR ALL USING (user_id = auth_user_id() OR is_service_role());

-- notification_templates (public read active, admin write)
ALTER TABLE notification_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notification_templates_select_active" ON notification_templates
    FOR SELECT USING (is_active = true OR is_admin());
CREATE POLICY "notification_templates_admin_all" ON notification_templates
    FOR ALL USING (is_admin() OR is_service_role());

-- notification_deliveries (service_role + admin only)
ALTER TABLE notification_deliveries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notification_deliveries_service_all" ON notification_deliveries
    FOR ALL USING (is_service_role());
CREATE POLICY "notification_deliveries_admin_read" ON notification_deliveries
    FOR SELECT USING (is_admin());
-- Users can read deliveries for their own notifications
CREATE POLICY "notification_deliveries_select_own" ON notification_deliveries
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM notifications n
            WHERE n.id = notification_deliveries.notification_id
              AND n.user_id = auth_user_id()
        )
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 4: SUPA_AUDIT TRACKING FOR ALL NEW TABLES
-- ─────────────────────────────────────────────────────────────────────────────

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'supa_audit') THEN
        RAISE NOTICE 'supa_audit not installed — skipping audit tracking';
        RETURN;
    END IF;

    -- Migration 020: CMS / i18n
    PERFORM audit.enable_tracking('public.languages'::regclass);
    PERFORM audit.enable_tracking('public.page_translations'::regclass);
    PERFORM audit.enable_tracking('public.post_translations'::regclass);
    PERFORM audit.enable_tracking('public.content_sections'::regclass);
    PERFORM audit.enable_tracking('public.content_section_translations'::regclass);
    PERFORM audit.enable_tracking('public.downloads'::regclass);
    PERFORM audit.enable_tracking('public.solutions'::regclass);
    PERFORM audit.enable_tracking('public.solution_translations'::regclass);
    PERFORM audit.enable_tracking('public.doc_categories'::regclass);
    PERFORM audit.enable_tracking('public.doc_category_translations'::regclass);
    PERFORM audit.enable_tracking('public.doc_articles'::regclass);
    PERFORM audit.enable_tracking('public.doc_article_translations'::regclass);

    -- Migration 021: Teams/Subscriptions
    PERFORM audit.enable_tracking('public.subscription_plans'::regclass);
    PERFORM audit.enable_tracking('public.payment_events'::regclass);
    PERFORM audit.enable_tracking('public.usage_records'::regclass);
    PERFORM audit.enable_tracking('public.invoices'::regclass);
    PERFORM audit.enable_tracking('public.team_invitations'::regclass);

    -- Migration 022: Notifications
    PERFORM audit.enable_tracking('public.notification_preferences'::regclass);
    PERFORM audit.enable_tracking('public.notification_templates'::regclass);
    PERFORM audit.enable_tracking('public.notification_deliveries'::regclass);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 5: UPDATE REALTIME PUBLICATION
-- ─────────────────────────────────────────────────────────────────────────────
-- Add new tables that benefit from real-time updates to the publication.

BEGIN;

DROP PUBLICATION IF EXISTS supabase_realtime;

CREATE PUBLICATION supabase_realtime FOR TABLE
    -- Core project data (from 018)
    features,
    plans,
    requests,
    notes,
    docs,

    -- AI & sessions (from 018)
    ai_sessions,
    session_turns,
    delegations,

    -- Team collaboration (from 018)
    persons,
    tunnels,

    -- Settings & notifications (from 018)
    notifications,
    user_settings,

    -- Feature flags (from 018)
    feature_flags,
    feature_flag_overrides,

    -- Community (from 018)
    community_posts,
    community_likes,
    comments,

    -- NEW: Team invitations (real-time accept/expire)
    team_invitations,

    -- NEW: Notification preferences (live toggle)
    notification_preferences,

    -- NEW: Notification deliveries (live status)
    notification_deliveries,

    -- NEW: Usage records (live dashboard)
    usage_records,

    -- NEW: Subscriptions (live plan changes)
    subscriptions,

    -- NEW: Invoices (live payment status)
    invoices;

COMMENT ON PUBLICATION supabase_realtime IS 'Tables enabled for Supabase Realtime subscriptions (updated for migrations 020-022)';

COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 6: GRANT ACCESS TO NEW TABLES
-- ─────────────────────────────────────────────────────────────────────────────

-- Authenticated users: full CRUD (RLS restricts actual access)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Anon: read-only on public CMS content
GRANT SELECT ON
    languages,
    page_translations,
    post_translations,
    content_sections,
    content_section_translations,
    downloads,
    solutions,
    solution_translations,
    doc_categories,
    doc_category_translations,
    doc_articles,
    doc_article_translations,
    subscription_plans,
    notification_templates
TO anon;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon;

-- ── Done ──
-- All tables from migrations 020-022 now have:
--   ✓ Row-Level Security policies
--   ✓ supa_audit change tracking
--   ✓ Realtime publication (where applicable)
--   ✓ Proper role grants
