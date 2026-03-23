-- 017_enable_rls.sql
-- Row-Level Security policies for ALL tables.
-- Maps Supabase auth.uid() (UUID) to internal users.id (BIGINT) via auth_uid column.
-- Idempotent: safe to run multiple times (uses IF NOT EXISTS and OR REPLACE).

-- =============================================================================
-- Step 1: Add auth_uid column to users table (bridges Supabase Auth ↔ internal IDs)
-- =============================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS auth_uid UUID UNIQUE;
CREATE INDEX IF NOT EXISTS idx_users_auth_uid ON users(auth_uid);

COMMENT ON COLUMN users.auth_uid IS 'Supabase Auth UUID, links to auth.uid()';

-- =============================================================================
-- Step 2: Helper function to resolve auth.uid() → internal user_id
-- =============================================================================

CREATE OR REPLACE FUNCTION auth_user_id() RETURNS BIGINT AS $$
    SELECT id FROM users WHERE auth_uid = auth.uid()
$$ LANGUAGE sql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION auth_user_id IS 'Returns the internal BIGINT user_id for the current Supabase JWT session';

-- =============================================================================
-- Step 3: Helper to check if current user is admin
-- =============================================================================

CREATE OR REPLACE FUNCTION is_admin() RETURNS BOOLEAN AS $$
    SELECT EXISTS (SELECT 1 FROM users WHERE id = auth_user_id() AND role = 'admin')
$$ LANGUAGE sql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION is_admin IS 'Returns true if the current authenticated user has admin role';

-- =============================================================================
-- Step 4: Helper to check service_role
-- =============================================================================

CREATE OR REPLACE FUNCTION is_service_role() RETURNS BOOLEAN AS $$
    SELECT COALESCE(
        current_setting('request.jwt.claims', true)::jsonb->>'role' = 'service_role',
        false
    )
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION is_service_role IS 'Returns true if the current request uses the service_role key';

-- =============================================================================
-- USER-OWNED TABLES (user_id = auth_user_id())
-- Full CRUD for own rows, service_role bypasses all.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 002_create_users.sql tables
-- ---------------------------------------------------------------------------

-- users (special: users can read/update their own row)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_select_own" ON users
    FOR SELECT USING (id = auth_user_id() OR is_service_role());
CREATE POLICY "users_update_own" ON users
    FOR UPDATE USING (id = auth_user_id());
CREATE POLICY "users_service_all" ON users
    FOR ALL USING (is_service_role());

-- passkeys
ALTER TABLE passkeys ENABLE ROW LEVEL SECURITY;

CREATE POLICY "passkeys_select_own" ON passkeys
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "passkeys_insert_own" ON passkeys
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "passkeys_update_own" ON passkeys
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "passkeys_delete_own" ON passkeys
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "passkeys_service_all" ON passkeys
    FOR ALL USING (is_service_role());

-- oauth_accounts
ALTER TABLE oauth_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "oauth_accounts_select_own" ON oauth_accounts
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "oauth_accounts_insert_own" ON oauth_accounts
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "oauth_accounts_update_own" ON oauth_accounts
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "oauth_accounts_delete_own" ON oauth_accounts
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "oauth_accounts_service_all" ON oauth_accounts
    FOR ALL USING (is_service_role());

-- device_tokens
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "device_tokens_select_own" ON device_tokens
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "device_tokens_insert_own" ON device_tokens
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "device_tokens_update_own" ON device_tokens
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "device_tokens_delete_own" ON device_tokens
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "device_tokens_service_all" ON device_tokens
    FOR ALL USING (is_service_role());

-- otp_codes
ALTER TABLE otp_codes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "otp_codes_select_own" ON otp_codes
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "otp_codes_insert_own" ON otp_codes
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "otp_codes_delete_own" ON otp_codes
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "otp_codes_service_all" ON otp_codes
    FOR ALL USING (is_service_role());

-- magic_link_tokens
ALTER TABLE magic_link_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "magic_link_tokens_select_own" ON magic_link_tokens
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "magic_link_tokens_insert_own" ON magic_link_tokens
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "magic_link_tokens_delete_own" ON magic_link_tokens
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "magic_link_tokens_service_all" ON magic_link_tokens
    FOR ALL USING (is_service_role());

-- user_verifications
ALTER TABLE user_verifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_verifications_select_own" ON user_verifications
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "user_verifications_insert_own" ON user_verifications
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "user_verifications_delete_own" ON user_verifications
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "user_verifications_service_all" ON user_verifications
    FOR ALL USING (is_service_role());

-- ---------------------------------------------------------------------------
-- 003_create_teams.sql tables
-- ---------------------------------------------------------------------------

-- teams (owner + members can read)
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;

CREATE POLICY "teams_select_member" ON teams
    FOR SELECT USING (
        owner_id = auth_user_id()
        OR id IN (SELECT team_id FROM memberships WHERE user_id = auth_user_id())
    );
CREATE POLICY "teams_insert_own" ON teams
    FOR INSERT WITH CHECK (owner_id = auth_user_id());
CREATE POLICY "teams_update_owner" ON teams
    FOR UPDATE USING (owner_id = auth_user_id());
CREATE POLICY "teams_delete_owner" ON teams
    FOR DELETE USING (owner_id = auth_user_id());
CREATE POLICY "teams_service_all" ON teams
    FOR ALL USING (is_service_role());

-- memberships
ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;

CREATE POLICY "memberships_select_own" ON memberships
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "memberships_select_team" ON memberships
    FOR SELECT USING (
        team_id IN (SELECT team_id FROM memberships AS m WHERE m.user_id = auth_user_id())
    );
CREATE POLICY "memberships_insert_own" ON memberships
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "memberships_update_own" ON memberships
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "memberships_delete_own" ON memberships
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "memberships_service_all" ON memberships
    FOR ALL USING (is_service_role());

-- ---------------------------------------------------------------------------
-- 004_create_projects.sql tables
-- ---------------------------------------------------------------------------

-- workspaces
ALTER TABLE workspaces ENABLE ROW LEVEL SECURITY;

CREATE POLICY "workspaces_select_own" ON workspaces
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "workspaces_insert_own" ON workspaces
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "workspaces_update_own" ON workspaces
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "workspaces_delete_own" ON workspaces
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "workspaces_service_all" ON workspaces
    FOR ALL USING (is_service_role());

-- workspace_teams (join table — accessible if you own the workspace or are a team member)
ALTER TABLE workspace_teams ENABLE ROW LEVEL SECURITY;

CREATE POLICY "workspace_teams_select" ON workspace_teams
    FOR SELECT USING (
        workspace_id IN (SELECT id FROM workspaces WHERE user_id = auth_user_id())
        OR team_id IN (SELECT team_id FROM memberships WHERE user_id = auth_user_id())
    );
CREATE POLICY "workspace_teams_insert" ON workspace_teams
    FOR INSERT WITH CHECK (
        workspace_id IN (SELECT id FROM workspaces WHERE user_id = auth_user_id())
    );
CREATE POLICY "workspace_teams_delete" ON workspace_teams
    FOR DELETE USING (
        workspace_id IN (SELECT id FROM workspaces WHERE user_id = auth_user_id())
    );
CREATE POLICY "workspace_teams_service_all" ON workspace_teams
    FOR ALL USING (is_service_role());

-- projects
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;

CREATE POLICY "projects_select_own" ON projects
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "projects_select_team" ON projects
    FOR SELECT USING (
        team_id IN (SELECT team_id FROM memberships WHERE user_id = auth_user_id())
    );
CREATE POLICY "projects_insert_own" ON projects
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "projects_update_own" ON projects
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "projects_delete_own" ON projects
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "projects_service_all" ON projects
    FOR ALL USING (is_service_role());

-- ---------------------------------------------------------------------------
-- 005_create_features.sql tables
-- ---------------------------------------------------------------------------

-- features
ALTER TABLE features ENABLE ROW LEVEL SECURITY;

CREATE POLICY "features_select_own" ON features
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "features_insert_own" ON features
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "features_update_own" ON features
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "features_delete_own" ON features
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "features_service_all" ON features
    FOR ALL USING (is_service_role());

-- plans
ALTER TABLE plans ENABLE ROW LEVEL SECURITY;

CREATE POLICY "plans_select_own" ON plans
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "plans_insert_own" ON plans
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "plans_update_own" ON plans
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "plans_delete_own" ON plans
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "plans_service_all" ON plans
    FOR ALL USING (is_service_role());

-- requests
ALTER TABLE requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "requests_select_own" ON requests
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "requests_insert_own" ON requests
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "requests_update_own" ON requests
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "requests_delete_own" ON requests
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "requests_service_all" ON requests
    FOR ALL USING (is_service_role());

-- epics
ALTER TABLE epics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "epics_select_own" ON epics
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "epics_insert_own" ON epics
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "epics_update_own" ON epics
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "epics_delete_own" ON epics
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "epics_service_all" ON epics
    FOR ALL USING (is_service_role());

-- stories
ALTER TABLE stories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "stories_select_own" ON stories
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "stories_insert_own" ON stories
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "stories_update_own" ON stories
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "stories_delete_own" ON stories
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "stories_service_all" ON stories
    FOR ALL USING (is_service_role());

-- tasks
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tasks_select_own" ON tasks
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "tasks_insert_own" ON tasks
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "tasks_update_own" ON tasks
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "tasks_delete_own" ON tasks
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "tasks_service_all" ON tasks
    FOR ALL USING (is_service_role());

-- ---------------------------------------------------------------------------
-- 006_create_notes.sql tables
-- ---------------------------------------------------------------------------

-- notes
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notes_select_own" ON notes
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "notes_insert_own" ON notes
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "notes_update_own" ON notes
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "notes_delete_own" ON notes
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "notes_service_all" ON notes
    FOR ALL USING (is_service_role());

-- note_revisions (accessible if the parent note is owned by the user)
ALTER TABLE note_revisions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "note_revisions_select_own" ON note_revisions
    FOR SELECT USING (
        user_id = auth_user_id()
        OR note_id IN (SELECT id FROM notes WHERE user_id = auth_user_id())
    );
CREATE POLICY "note_revisions_insert_own" ON note_revisions
    FOR INSERT WITH CHECK (
        user_id = auth_user_id()
        OR note_id IN (SELECT id FROM notes WHERE user_id = auth_user_id())
    );
CREATE POLICY "note_revisions_service_all" ON note_revisions
    FOR ALL USING (is_service_role());

-- docs
ALTER TABLE docs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "docs_select_own" ON docs
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "docs_select_published" ON docs
    FOR SELECT USING (published = true);
CREATE POLICY "docs_insert_own" ON docs
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "docs_update_own" ON docs
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "docs_delete_own" ON docs
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "docs_service_all" ON docs
    FOR ALL USING (is_service_role());

-- ---------------------------------------------------------------------------
-- 007_create_agents.sql tables
-- ---------------------------------------------------------------------------

-- agents
ALTER TABLE agents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "agents_select_own" ON agents
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "agents_select_team" ON agents
    FOR SELECT USING (
        team_id IN (SELECT team_id FROM memberships WHERE user_id = auth_user_id())
    );
CREATE POLICY "agents_select_public" ON agents
    FOR SELECT USING (visibility = 'public');
CREATE POLICY "agents_insert_own" ON agents
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "agents_update_own" ON agents
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "agents_delete_own" ON agents
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "agents_service_all" ON agents
    FOR ALL USING (is_service_role());

-- skills
ALTER TABLE skills ENABLE ROW LEVEL SECURITY;

CREATE POLICY "skills_select_own" ON skills
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "skills_select_team" ON skills
    FOR SELECT USING (
        team_id IN (SELECT team_id FROM memberships WHERE user_id = auth_user_id())
    );
CREATE POLICY "skills_select_public" ON skills
    FOR SELECT USING (visibility = 'public');
CREATE POLICY "skills_insert_own" ON skills
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "skills_update_own" ON skills
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "skills_delete_own" ON skills
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "skills_service_all" ON skills
    FOR ALL USING (is_service_role());

-- workflows
ALTER TABLE workflows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "workflows_select_own" ON workflows
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "workflows_insert_own" ON workflows
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "workflows_update_own" ON workflows
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "workflows_delete_own" ON workflows
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "workflows_service_all" ON workflows
    FOR ALL USING (is_service_role());

-- project_skills (join table)
ALTER TABLE project_skills ENABLE ROW LEVEL SECURITY;

CREATE POLICY "project_skills_select" ON project_skills
    FOR SELECT USING (
        project_id IN (SELECT id FROM projects WHERE user_id = auth_user_id())
    );
CREATE POLICY "project_skills_insert" ON project_skills
    FOR INSERT WITH CHECK (
        project_id IN (SELECT id FROM projects WHERE user_id = auth_user_id())
    );
CREATE POLICY "project_skills_delete" ON project_skills
    FOR DELETE USING (
        project_id IN (SELECT id FROM projects WHERE user_id = auth_user_id())
    );
CREATE POLICY "project_skills_service_all" ON project_skills
    FOR ALL USING (is_service_role());

-- project_agents (join table)
ALTER TABLE project_agents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "project_agents_select" ON project_agents
    FOR SELECT USING (
        project_id IN (SELECT id FROM projects WHERE user_id = auth_user_id())
    );
CREATE POLICY "project_agents_insert" ON project_agents
    FOR INSERT WITH CHECK (
        project_id IN (SELECT id FROM projects WHERE user_id = auth_user_id())
    );
CREATE POLICY "project_agents_delete" ON project_agents
    FOR DELETE USING (
        project_id IN (SELECT id FROM projects WHERE user_id = auth_user_id())
    );
CREATE POLICY "project_agents_service_all" ON project_agents
    FOR ALL USING (is_service_role());

-- ---------------------------------------------------------------------------
-- 008_create_health.sql tables
-- ---------------------------------------------------------------------------

-- health_profiles
ALTER TABLE health_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "health_profiles_select_own" ON health_profiles
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "health_profiles_insert_own" ON health_profiles
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "health_profiles_update_own" ON health_profiles
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "health_profiles_delete_own" ON health_profiles
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "health_profiles_service_all" ON health_profiles
    FOR ALL USING (is_service_role());

-- water_logs
ALTER TABLE water_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "water_logs_select_own" ON water_logs
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "water_logs_insert_own" ON water_logs
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "water_logs_update_own" ON water_logs
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "water_logs_delete_own" ON water_logs
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "water_logs_service_all" ON water_logs
    FOR ALL USING (is_service_role());

-- meal_logs
ALTER TABLE meal_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "meal_logs_select_own" ON meal_logs
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "meal_logs_insert_own" ON meal_logs
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "meal_logs_update_own" ON meal_logs
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "meal_logs_delete_own" ON meal_logs
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "meal_logs_service_all" ON meal_logs
    FOR ALL USING (is_service_role());

-- caffeine_logs
ALTER TABLE caffeine_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "caffeine_logs_select_own" ON caffeine_logs
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "caffeine_logs_insert_own" ON caffeine_logs
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "caffeine_logs_update_own" ON caffeine_logs
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "caffeine_logs_delete_own" ON caffeine_logs
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "caffeine_logs_service_all" ON caffeine_logs
    FOR ALL USING (is_service_role());

-- pomodoro_sessions
ALTER TABLE pomodoro_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pomodoro_sessions_select_own" ON pomodoro_sessions
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "pomodoro_sessions_insert_own" ON pomodoro_sessions
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "pomodoro_sessions_update_own" ON pomodoro_sessions
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "pomodoro_sessions_delete_own" ON pomodoro_sessions
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "pomodoro_sessions_service_all" ON pomodoro_sessions
    FOR ALL USING (is_service_role());

-- sleep_configs
ALTER TABLE sleep_configs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sleep_configs_select_own" ON sleep_configs
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "sleep_configs_insert_own" ON sleep_configs
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "sleep_configs_update_own" ON sleep_configs
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "sleep_configs_delete_own" ON sleep_configs
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "sleep_configs_service_all" ON sleep_configs
    FOR ALL USING (is_service_role());

-- sleep_logs
ALTER TABLE sleep_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sleep_logs_select_own" ON sleep_logs
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "sleep_logs_insert_own" ON sleep_logs
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "sleep_logs_update_own" ON sleep_logs
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "sleep_logs_delete_own" ON sleep_logs
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "sleep_logs_service_all" ON sleep_logs
    FOR ALL USING (is_service_role());

-- health_snapshots
ALTER TABLE health_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "health_snapshots_select_own" ON health_snapshots
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "health_snapshots_insert_own" ON health_snapshots
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "health_snapshots_update_own" ON health_snapshots
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "health_snapshots_delete_own" ON health_snapshots
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "health_snapshots_service_all" ON health_snapshots
    FOR ALL USING (is_service_role());

-- ---------------------------------------------------------------------------
-- 009_create_sessions.sql tables
-- ---------------------------------------------------------------------------

-- ai_sessions
ALTER TABLE ai_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ai_sessions_select_own" ON ai_sessions
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "ai_sessions_insert_own" ON ai_sessions
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "ai_sessions_update_own" ON ai_sessions
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "ai_sessions_delete_own" ON ai_sessions
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "ai_sessions_service_all" ON ai_sessions
    FOR ALL USING (is_service_role());

-- session_turns (accessible if the parent session is owned by the user)
ALTER TABLE session_turns ENABLE ROW LEVEL SECURITY;

CREATE POLICY "session_turns_select_own" ON session_turns
    FOR SELECT USING (
        session_id IN (SELECT id FROM ai_sessions WHERE user_id = auth_user_id())
    );
CREATE POLICY "session_turns_insert_own" ON session_turns
    FOR INSERT WITH CHECK (
        session_id IN (SELECT id FROM ai_sessions WHERE user_id = auth_user_id())
    );
CREATE POLICY "session_turns_service_all" ON session_turns
    FOR ALL USING (is_service_role());

-- persons
ALTER TABLE persons ENABLE ROW LEVEL SECURITY;

CREATE POLICY "persons_select_own" ON persons
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "persons_insert_own" ON persons
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "persons_update_own" ON persons
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "persons_delete_own" ON persons
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "persons_service_all" ON persons
    FOR ALL USING (is_service_role());

-- delegations
ALTER TABLE delegations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "delegations_select_own" ON delegations
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "delegations_insert_own" ON delegations
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "delegations_update_own" ON delegations
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "delegations_delete_own" ON delegations
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "delegations_service_all" ON delegations
    FOR ALL USING (is_service_role());

-- assignment_rules (accessible if the project is owned by user)
ALTER TABLE assignment_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "assignment_rules_select_own" ON assignment_rules
    FOR SELECT USING (
        project_id IN (SELECT id FROM projects WHERE user_id = auth_user_id())
    );
CREATE POLICY "assignment_rules_insert_own" ON assignment_rules
    FOR INSERT WITH CHECK (
        project_id IN (SELECT id FROM projects WHERE user_id = auth_user_id())
    );
CREATE POLICY "assignment_rules_update_own" ON assignment_rules
    FOR UPDATE USING (
        project_id IN (SELECT id FROM projects WHERE user_id = auth_user_id())
    );
CREATE POLICY "assignment_rules_delete_own" ON assignment_rules
    FOR DELETE USING (
        project_id IN (SELECT id FROM projects WHERE user_id = auth_user_id())
    );
CREATE POLICY "assignment_rules_service_all" ON assignment_rules
    FOR ALL USING (is_service_role());

-- ---------------------------------------------------------------------------
-- 010_create_settings.sql tables
-- ---------------------------------------------------------------------------

-- user_settings
ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_settings_select_own" ON user_settings
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "user_settings_insert_own" ON user_settings
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "user_settings_update_own" ON user_settings
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "user_settings_delete_own" ON user_settings
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "user_settings_service_all" ON user_settings
    FOR ALL USING (is_service_role());

-- system_settings (admin-only)
ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "system_settings_select_all" ON system_settings
    FOR SELECT USING (true);
CREATE POLICY "system_settings_admin_all" ON system_settings
    FOR ALL USING (is_admin() OR is_service_role());

-- subscriptions
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "subscriptions_select_own" ON subscriptions
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "subscriptions_insert_own" ON subscriptions
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "subscriptions_update_own" ON subscriptions
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "subscriptions_delete_own" ON subscriptions
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "subscriptions_service_all" ON subscriptions
    FOR ALL USING (is_service_role());

-- user_integrations
ALTER TABLE user_integrations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_integrations_select_own" ON user_integrations
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "user_integrations_insert_own" ON user_integrations
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "user_integrations_update_own" ON user_integrations
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "user_integrations_delete_own" ON user_integrations
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "user_integrations_service_all" ON user_integrations
    FOR ALL USING (is_service_role());

-- push_subscriptions
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "push_subscriptions_select_own" ON push_subscriptions
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "push_subscriptions_insert_own" ON push_subscriptions
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "push_subscriptions_update_own" ON push_subscriptions
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "push_subscriptions_delete_own" ON push_subscriptions
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "push_subscriptions_service_all" ON push_subscriptions
    FOR ALL USING (is_service_role());

-- ---------------------------------------------------------------------------
-- 011_create_api_collections.sql tables
-- ---------------------------------------------------------------------------

-- api_collections
ALTER TABLE api_collections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "api_collections_select_own" ON api_collections
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "api_collections_select_team" ON api_collections
    FOR SELECT USING (
        team_id IN (SELECT team_id FROM memberships WHERE user_id = auth_user_id())
    );
CREATE POLICY "api_collections_select_public" ON api_collections
    FOR SELECT USING (visibility = 'public');
CREATE POLICY "api_collections_insert_own" ON api_collections
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "api_collections_update_own" ON api_collections
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "api_collections_delete_own" ON api_collections
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "api_collections_service_all" ON api_collections
    FOR ALL USING (is_service_role());

-- api_endpoints
ALTER TABLE api_endpoints ENABLE ROW LEVEL SECURITY;

CREATE POLICY "api_endpoints_select_own" ON api_endpoints
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "api_endpoints_select_via_collection" ON api_endpoints
    FOR SELECT USING (
        collection_id IN (
            SELECT id FROM api_collections
            WHERE user_id = auth_user_id()
               OR team_id IN (SELECT team_id FROM memberships WHERE user_id = auth_user_id())
               OR visibility = 'public'
        )
    );
CREATE POLICY "api_endpoints_insert_own" ON api_endpoints
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "api_endpoints_update_own" ON api_endpoints
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "api_endpoints_delete_own" ON api_endpoints
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "api_endpoints_service_all" ON api_endpoints
    FOR ALL USING (is_service_role());

-- api_environments
ALTER TABLE api_environments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "api_environments_select_own" ON api_environments
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "api_environments_insert_own" ON api_environments
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "api_environments_update_own" ON api_environments
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "api_environments_delete_own" ON api_environments
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "api_environments_service_all" ON api_environments
    FOR ALL USING (is_service_role());

-- ---------------------------------------------------------------------------
-- 012_create_presentations.sql tables
-- ---------------------------------------------------------------------------

-- presentations
ALTER TABLE presentations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "presentations_select_own" ON presentations
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "presentations_select_team" ON presentations
    FOR SELECT USING (
        team_id IN (SELECT team_id FROM memberships WHERE user_id = auth_user_id())
    );
CREATE POLICY "presentations_select_public" ON presentations
    FOR SELECT USING (visibility = 'public');
CREATE POLICY "presentations_insert_own" ON presentations
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "presentations_update_own" ON presentations
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "presentations_delete_own" ON presentations
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "presentations_service_all" ON presentations
    FOR ALL USING (is_service_role());

-- presentation_slides
ALTER TABLE presentation_slides ENABLE ROW LEVEL SECURITY;

CREATE POLICY "presentation_slides_select_own" ON presentation_slides
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "presentation_slides_select_via_presentation" ON presentation_slides
    FOR SELECT USING (
        presentation_id IN (
            SELECT id FROM presentations
            WHERE user_id = auth_user_id()
               OR team_id IN (SELECT team_id FROM memberships WHERE user_id = auth_user_id())
               OR visibility = 'public'
        )
    );
CREATE POLICY "presentation_slides_insert_own" ON presentation_slides
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "presentation_slides_update_own" ON presentation_slides
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "presentation_slides_delete_own" ON presentation_slides
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "presentation_slides_service_all" ON presentation_slides
    FOR ALL USING (is_service_role());

-- ---------------------------------------------------------------------------
-- 013_create_community.sql tables
-- ---------------------------------------------------------------------------

-- community_posts
ALTER TABLE community_posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "community_posts_select_published" ON community_posts
    FOR SELECT USING (status = 'published');
CREATE POLICY "community_posts_select_own" ON community_posts
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "community_posts_insert_own" ON community_posts
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "community_posts_update_own" ON community_posts
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "community_posts_delete_own" ON community_posts
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "community_posts_service_all" ON community_posts
    FOR ALL USING (is_service_role());
CREATE POLICY "community_posts_admin_all" ON community_posts
    FOR ALL USING (is_admin());

-- community_likes
ALTER TABLE community_likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "community_likes_select_own" ON community_likes
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "community_likes_select_all" ON community_likes
    FOR SELECT USING (
        post_id IN (SELECT id FROM community_posts WHERE status = 'published')
    );
CREATE POLICY "community_likes_insert_own" ON community_likes
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "community_likes_delete_own" ON community_likes
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "community_likes_service_all" ON community_likes
    FOR ALL USING (is_service_role());

-- comments
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "comments_select_own" ON comments
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "comments_select_active" ON comments
    FOR SELECT USING (status = 'active');
CREATE POLICY "comments_insert_own" ON comments
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "comments_update_own" ON comments
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "comments_delete_own" ON comments
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "comments_service_all" ON comments
    FOR ALL USING (is_service_role());

-- issues (reporter can see their own, admin can see all)
ALTER TABLE issues ENABLE ROW LEVEL SECURITY;

CREATE POLICY "issues_select_own" ON issues
    FOR SELECT USING (reporter_user_id = auth_user_id());
CREATE POLICY "issues_insert_own" ON issues
    FOR INSERT WITH CHECK (reporter_user_id = auth_user_id());
CREATE POLICY "issues_update_own" ON issues
    FOR UPDATE USING (reporter_user_id = auth_user_id());
CREATE POLICY "issues_admin_all" ON issues
    FOR ALL USING (is_admin() OR is_service_role());

-- sponsors (admin-only write, public read)
ALTER TABLE sponsors ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sponsors_select_public" ON sponsors
    FOR SELECT USING (status = 'active');
CREATE POLICY "sponsors_admin_all" ON sponsors
    FOR ALL USING (is_admin() OR is_service_role());

-- contact_messages (admin-only, no user_id)
ALTER TABLE contact_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "contact_messages_insert_anon" ON contact_messages
    FOR INSERT WITH CHECK (true);
CREATE POLICY "contact_messages_admin_all" ON contact_messages
    FOR ALL USING (is_admin() OR is_service_role());

-- pages (admin-only write, public read for published)
ALTER TABLE pages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pages_select_published" ON pages
    FOR SELECT USING (status = 'published');
CREATE POLICY "pages_admin_all" ON pages
    FOR ALL USING (is_admin() OR is_service_role());

-- posts (admin-only write, public read for published)
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "posts_select_published" ON posts
    FOR SELECT USING (status = 'published');
CREATE POLICY "posts_admin_all" ON posts
    FOR ALL USING (is_admin() OR is_service_role());

-- verification_types (read-only lookup, admin write)
ALTER TABLE verification_types ENABLE ROW LEVEL SECURITY;

CREATE POLICY "verification_types_select_all" ON verification_types
    FOR SELECT USING (true);
CREATE POLICY "verification_types_admin_all" ON verification_types
    FOR ALL USING (is_admin() OR is_service_role());

-- ---------------------------------------------------------------------------
-- 014_create_admin.sql tables
-- ---------------------------------------------------------------------------

-- badge_definitions (admin-only write, public read)
ALTER TABLE badge_definitions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "badge_definitions_select_all" ON badge_definitions
    FOR SELECT USING (true);
CREATE POLICY "badge_definitions_admin_all" ON badge_definitions
    FOR ALL USING (is_admin() OR is_service_role());

-- user_badges
ALTER TABLE user_badges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_badges_select_own" ON user_badges
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "user_badges_select_public" ON user_badges
    FOR SELECT USING (true);
CREATE POLICY "user_badges_admin_all" ON user_badges
    FOR ALL USING (is_admin() OR is_service_role());

-- user_wallets
ALTER TABLE user_wallets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_wallets_select_own" ON user_wallets
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "user_wallets_insert_own" ON user_wallets
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "user_wallets_update_own" ON user_wallets
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "user_wallets_service_all" ON user_wallets
    FOR ALL USING (is_service_role());

-- points_transactions
ALTER TABLE points_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "points_transactions_select_own" ON points_transactions
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "points_transactions_service_all" ON points_transactions
    FOR ALL USING (is_service_role());

-- github_repos (admin-only)
ALTER TABLE github_repos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "github_repos_select_all" ON github_repos
    FOR SELECT USING (true);
CREATE POLICY "github_repos_admin_all" ON github_repos
    FOR ALL USING (is_admin() OR is_service_role());

-- github_issues (admin-only write, public read)
ALTER TABLE github_issues ENABLE ROW LEVEL SECURITY;

CREATE POLICY "github_issues_select_all" ON github_issues
    FOR SELECT USING (true);
CREATE POLICY "github_issues_admin_all" ON github_issues
    FOR ALL USING (is_admin() OR is_service_role());

-- ---------------------------------------------------------------------------
-- 015_create_tunnels.sql tables
-- ---------------------------------------------------------------------------

-- tunnels
ALTER TABLE tunnels ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tunnels_select_own" ON tunnels
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "tunnels_select_team" ON tunnels
    FOR SELECT USING (
        team_id IN (SELECT team_id FROM memberships WHERE user_id = auth_user_id())
    );
CREATE POLICY "tunnels_insert_own" ON tunnels
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "tunnels_update_own" ON tunnels
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "tunnels_delete_own" ON tunnels
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "tunnels_service_all" ON tunnels
    FOR ALL USING (is_service_role());

-- shared_contents
ALTER TABLE shared_contents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "shared_contents_select_own" ON shared_contents
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "shared_contents_select_public" ON shared_contents
    FOR SELECT USING (visibility = 'public' OR visibility = 'unlisted');
CREATE POLICY "shared_contents_select_team" ON shared_contents
    FOR SELECT USING (
        team_id IN (SELECT team_id FROM memberships WHERE user_id = auth_user_id())
    );
CREATE POLICY "shared_contents_insert_own" ON shared_contents
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "shared_contents_update_own" ON shared_contents
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "shared_contents_delete_own" ON shared_contents
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "shared_contents_service_all" ON shared_contents
    FOR ALL USING (is_service_role());

-- share_comments
ALTER TABLE share_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "share_comments_select_own" ON share_comments
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "share_comments_select_public" ON share_comments
    FOR SELECT USING (
        share_id IN (SELECT id FROM shared_contents WHERE visibility IN ('public', 'unlisted'))
    );
CREATE POLICY "share_comments_insert_own" ON share_comments
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "share_comments_update_own" ON share_comments
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "share_comments_delete_own" ON share_comments
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "share_comments_service_all" ON share_comments
    FOR ALL USING (is_service_role());

-- team_shares
ALTER TABLE team_shares ENABLE ROW LEVEL SECURITY;

CREATE POLICY "team_shares_select_own" ON team_shares
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "team_shares_select_team" ON team_shares
    FOR SELECT USING (
        team_id IN (SELECT team_id FROM memberships WHERE user_id = auth_user_id())
    );
CREATE POLICY "team_shares_insert_own" ON team_shares
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "team_shares_update_own" ON team_shares
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "team_shares_delete_own" ON team_shares
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "team_shares_service_all" ON team_shares
    FOR ALL USING (is_service_role());

-- content_views (public insert for analytics, admin read)
ALTER TABLE content_views ENABLE ROW LEVEL SECURITY;

CREATE POLICY "content_views_insert_anon" ON content_views
    FOR INSERT WITH CHECK (true);
CREATE POLICY "content_views_select_owner" ON content_views
    FOR SELECT USING (
        content_id IN (SELECT id FROM shared_contents WHERE user_id = auth_user_id())
    );
CREATE POLICY "content_views_service_all" ON content_views
    FOR ALL USING (is_service_role());

-- custom_domains
ALTER TABLE custom_domains ENABLE ROW LEVEL SECURITY;

CREATE POLICY "custom_domains_select_own" ON custom_domains
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "custom_domains_insert_own" ON custom_domains
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "custom_domains_update_own" ON custom_domains
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "custom_domains_delete_own" ON custom_domains
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "custom_domains_service_all" ON custom_domains
    FOR ALL USING (is_service_role());

-- action_histories
ALTER TABLE action_histories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "action_histories_select_own" ON action_histories
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "action_histories_insert_own" ON action_histories
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "action_histories_service_all" ON action_histories
    FOR ALL USING (is_service_role());

-- action_logs
ALTER TABLE action_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "action_logs_select_own" ON action_logs
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "action_logs_insert_own" ON action_logs
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "action_logs_service_all" ON action_logs
    FOR ALL USING (is_service_role());

-- mcp_event_logs
ALTER TABLE mcp_event_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mcp_event_logs_select_own" ON mcp_event_logs
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "mcp_event_logs_insert_own" ON mcp_event_logs
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "mcp_event_logs_service_all" ON mcp_event_logs
    FOR ALL USING (is_service_role());

-- sync_logs
ALTER TABLE sync_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sync_logs_select_own" ON sync_logs
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "sync_logs_insert_own" ON sync_logs
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "sync_logs_service_all" ON sync_logs
    FOR ALL USING (is_service_role());

-- conflict_logs
ALTER TABLE conflict_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "conflict_logs_select_own" ON conflict_logs
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "conflict_logs_insert_own" ON conflict_logs
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "conflict_logs_service_all" ON conflict_logs
    FOR ALL USING (is_service_role());

-- repo_workspaces
ALTER TABLE repo_workspaces ENABLE ROW LEVEL SECURITY;

CREATE POLICY "repo_workspaces_select_own" ON repo_workspaces
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "repo_workspaces_insert_own" ON repo_workspaces
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "repo_workspaces_update_own" ON repo_workspaces
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "repo_workspaces_delete_own" ON repo_workspaces
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "repo_workspaces_service_all" ON repo_workspaces
    FOR ALL USING (is_service_role());

-- notifications
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notifications_select_own" ON notifications
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "notifications_insert_own" ON notifications
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "notifications_update_own" ON notifications
    FOR UPDATE USING (user_id = auth_user_id());
CREATE POLICY "notifications_delete_own" ON notifications
    FOR DELETE USING (user_id = auth_user_id());
CREATE POLICY "notifications_service_all" ON notifications
    FOR ALL USING (is_service_role());

-- packs (public read, admin/service write — no user_id column)
ALTER TABLE packs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "packs_select_all" ON packs
    FOR SELECT USING (true);
CREATE POLICY "packs_admin_all" ON packs
    FOR ALL USING (is_admin() OR is_service_role());

-- ---------------------------------------------------------------------------
-- 016_create_feature_flags.sql tables
-- ---------------------------------------------------------------------------

-- feature_flags (admin-only CRUD, authenticated users can read enabled flags)
ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "feature_flags_select_enabled" ON feature_flags
    FOR SELECT USING (enabled = true OR is_admin());
CREATE POLICY "feature_flags_admin_all" ON feature_flags
    FOR ALL USING (is_admin() OR is_service_role());

-- feature_flag_overrides
ALTER TABLE feature_flag_overrides ENABLE ROW LEVEL SECURITY;

CREATE POLICY "feature_flag_overrides_select_own" ON feature_flag_overrides
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "feature_flag_overrides_admin_all" ON feature_flag_overrides
    FOR ALL USING (is_admin() OR is_service_role());

-- experiments (admin manages, users can read running experiments)
ALTER TABLE experiments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "experiments_select_running" ON experiments
    FOR SELECT USING (status = 'running' OR is_admin());
CREATE POLICY "experiments_admin_all" ON experiments
    FOR ALL USING (is_admin() OR is_service_role());

-- experiment_assignments
ALTER TABLE experiment_assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "experiment_assignments_select_own" ON experiment_assignments
    FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "experiment_assignments_insert_own" ON experiment_assignments
    FOR INSERT WITH CHECK (user_id = auth_user_id());
CREATE POLICY "experiment_assignments_service_all" ON experiment_assignments
    FOR ALL USING (is_service_role());

-- =============================================================================
-- Grant authenticated role access to all tables
-- (RLS policies will restrict what they can actually see/do)
-- =============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Anon role: read-only on public content
GRANT SELECT ON
    community_posts, community_likes, comments,
    shared_contents, content_views, share_comments,
    docs, agents, skills, api_collections,
    presentations, sponsors, pages, posts,
    badge_definitions, user_badges,
    github_repos, github_issues,
    verification_types, system_settings, packs,
    feature_flags, experiments
TO anon;

-- Anon can insert contact messages and content views
GRANT INSERT ON contact_messages TO anon;
GRANT INSERT ON content_views TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon;
