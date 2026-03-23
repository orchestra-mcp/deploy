-- 003_create_teams.sql
-- Teams and memberships.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Teams
-- =============================================================================

CREATE TABLE IF NOT EXISTS teams (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT            NOT NULL,
    slug            TEXT            UNIQUE NOT NULL,
    description     TEXT            DEFAULT '',
    avatar          TEXT            DEFAULT '',
    metadata        JSONB           DEFAULT '{}',
    owner_id        BIGINT          REFERENCES users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_teams_slug       ON teams (slug);
CREATE INDEX IF NOT EXISTS idx_teams_owner_id   ON teams (owner_id);
CREATE INDEX IF NOT EXISTS idx_teams_deleted_at ON teams (deleted_at);

COMMENT ON TABLE teams IS 'Organizational teams that own projects and share resources';

-- =============================================================================
-- Memberships
-- =============================================================================

CREATE TABLE IF NOT EXISTS memberships (
    id              BIGSERIAL       PRIMARY KEY,
    team_id         UUID            NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role            TEXT            DEFAULT 'member'
                                    CHECK (role IN ('owner', 'admin', 'manager', 'member', 'viewer')),
    permissions     JSONB           DEFAULT '{}',
    joined_at       TIMESTAMPTZ     DEFAULT NOW(),
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_memberships_team_user
    ON memberships (team_id, user_id);
CREATE INDEX IF NOT EXISTS idx_memberships_user_id ON memberships (user_id);

COMMENT ON TABLE memberships IS 'Team membership with role-based permissions';
COMMENT ON COLUMN memberships.role IS 'One of: owner, admin, manager, member, viewer';
