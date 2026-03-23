-- 004_create_projects.sql
-- Projects and workspaces.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Workspaces
-- =============================================================================

CREATE TABLE IF NOT EXISTS workspaces (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            TEXT            NOT NULL,
    description     TEXT            DEFAULT '',
    metadata        JSONB           DEFAULT '{}',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_workspaces_user_id    ON workspaces (user_id);
CREATE INDEX IF NOT EXISTS idx_workspaces_deleted_at ON workspaces (deleted_at);

COMMENT ON TABLE workspaces IS 'Logical groupings of projects and folders';

-- =============================================================================
-- Workspace-Team associations
-- =============================================================================

CREATE TABLE IF NOT EXISTS workspace_teams (
    workspace_id    UUID            NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    team_id         UUID            NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    PRIMARY KEY (workspace_id, team_id)
);

COMMENT ON TABLE workspace_teams IS 'Many-to-many link between workspaces and teams';

-- =============================================================================
-- Projects
-- =============================================================================

CREATE TABLE IF NOT EXISTS projects (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    team_id         UUID            REFERENCES teams(id) ON DELETE SET NULL,
    workspace_id    UUID            REFERENCES workspaces(id) ON DELETE SET NULL,
    name            TEXT            NOT NULL,
    slug            TEXT            NOT NULL,
    description     TEXT            DEFAULT '',
    body            TEXT            DEFAULT '',
    metadata        JSONB           DEFAULT '{}',
    sync_status     TEXT            DEFAULT 'synced'
                                    CHECK (sync_status IN ('synced', 'pending', 'conflict', 'error')),
    last_synced_at  TIMESTAMPTZ,
    stats           JSONB           DEFAULT '{}',
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_projects_user_slug
    ON projects (user_id, slug);
CREATE INDEX IF NOT EXISTS idx_projects_team_id      ON projects (team_id);
CREATE INDEX IF NOT EXISTS idx_projects_workspace_id ON projects (workspace_id);
CREATE INDEX IF NOT EXISTS idx_projects_deleted_at   ON projects (deleted_at);

COMMENT ON TABLE projects IS 'Top-level project containers with sync and versioning';
COMMENT ON COLUMN projects.slug IS 'URL-friendly project identifier, unique per user';
