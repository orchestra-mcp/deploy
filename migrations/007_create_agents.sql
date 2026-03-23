-- 007_create_agents.sql
-- Agents, skills, workflows, and project associations.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Agents
-- =============================================================================

CREATE TABLE IF NOT EXISTS agents (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    team_id         UUID            REFERENCES teams(id) ON DELETE SET NULL,
    name            TEXT            NOT NULL,
    slug            TEXT            NOT NULL DEFAULT '',
    description     TEXT            DEFAULT '',
    system_prompt   TEXT            DEFAULT '',
    model           TEXT            DEFAULT '',
    temperature     FLOAT           DEFAULT 0.7,
    max_tokens      INTEGER         DEFAULT 4096,
    content         TEXT            DEFAULT '',
    scope           TEXT            DEFAULT 'personal'
                                    CHECK (scope IN ('personal', 'team', 'global')),
    public_url      TEXT            DEFAULT '',
    icon            TEXT            DEFAULT '',
    color           TEXT            DEFAULT '',
    visibility      TEXT            DEFAULT 'private'
                                    CHECK (visibility IN ('private', 'team', 'public')),
    version         INTEGER         DEFAULT 1,
    synced_at       TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_agents_user_id    ON agents (user_id);
CREATE INDEX IF NOT EXISTS idx_agents_team_id    ON agents (team_id);
CREATE INDEX IF NOT EXISTS idx_agents_slug       ON agents (slug);
CREATE INDEX IF NOT EXISTS idx_agents_scope      ON agents (scope);
CREATE INDEX IF NOT EXISTS idx_agents_visibility ON agents (visibility);
CREATE INDEX IF NOT EXISTS idx_agents_deleted_at ON agents (deleted_at);

COMMENT ON TABLE agents IS 'AI agent definitions with system prompts and model configs';

-- =============================================================================
-- Skills
-- =============================================================================

CREATE TABLE IF NOT EXISTS skills (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    team_id         UUID            REFERENCES teams(id) ON DELETE SET NULL,
    name            TEXT            NOT NULL,
    slug            TEXT            NOT NULL DEFAULT '',
    description     TEXT            DEFAULT '',
    content         TEXT            DEFAULT '',
    scope           TEXT            DEFAULT 'personal'
                                    CHECK (scope IN ('personal', 'team', 'global')),
    public_url      TEXT            DEFAULT '',
    icon            TEXT            DEFAULT '',
    color           TEXT            DEFAULT '',
    stacks          JSONB           DEFAULT '[]',
    visibility      TEXT            DEFAULT 'private'
                                    CHECK (visibility IN ('private', 'team', 'public')),
    version         INTEGER         DEFAULT 1,
    synced_at       TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_skills_user_id    ON skills (user_id);
CREATE INDEX IF NOT EXISTS idx_skills_team_id    ON skills (team_id);
CREATE INDEX IF NOT EXISTS idx_skills_slug       ON skills (slug);
CREATE INDEX IF NOT EXISTS idx_skills_scope      ON skills (scope);
CREATE INDEX IF NOT EXISTS idx_skills_visibility ON skills (visibility);
CREATE INDEX IF NOT EXISTS idx_skills_deleted_at ON skills (deleted_at);

COMMENT ON TABLE skills IS 'Reusable skill definitions (slash commands) with markdown content';

-- =============================================================================
-- Workflows
-- =============================================================================

CREATE TABLE IF NOT EXISTS workflows (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id      UUID            REFERENCES projects(id) ON DELETE SET NULL,
    name            TEXT            NOT NULL,
    slug            TEXT            NOT NULL DEFAULT '',
    description     TEXT            DEFAULT '',
    initial_state   TEXT            DEFAULT '',
    config          JSONB           DEFAULT '{}',
    version         INTEGER         DEFAULT 1,
    enabled         BOOLEAN         DEFAULT true,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_workflows_user_id    ON workflows (user_id);
CREATE INDEX IF NOT EXISTS idx_workflows_project_id ON workflows (project_id);
CREATE INDEX IF NOT EXISTS idx_workflows_slug       ON workflows (slug);
CREATE INDEX IF NOT EXISTS idx_workflows_enabled    ON workflows (enabled) WHERE enabled = true;
CREATE INDEX IF NOT EXISTS idx_workflows_deleted_at ON workflows (deleted_at);

COMMENT ON TABLE workflows IS 'Workflow definitions with state machine configuration';

-- =============================================================================
-- Project-Skill associations
-- =============================================================================

CREATE TABLE IF NOT EXISTS project_skills (
    project_id      UUID            NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    skill_id        UUID            NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    PRIMARY KEY (project_id, skill_id)
);

COMMENT ON TABLE project_skills IS 'Many-to-many link between projects and skills';

-- =============================================================================
-- Project-Agent associations
-- =============================================================================

CREATE TABLE IF NOT EXISTS project_agents (
    project_id      UUID            NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    agent_id        UUID            NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    PRIMARY KEY (project_id, agent_id)
);

COMMENT ON TABLE project_agents IS 'Many-to-many link between projects and agents';
