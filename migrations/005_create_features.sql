-- 005_create_features.sql
-- Features, plans, requests, epics, stories, and tasks.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Features
-- =============================================================================

CREATE TABLE IF NOT EXISTS features (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_slug    TEXT            NOT NULL,
    feature_id      TEXT            NOT NULL,
    title           TEXT            NOT NULL,
    description     TEXT            DEFAULT '',
    status          TEXT            DEFAULT 'backlog'
                                    CHECK (status IN (
                                        'backlog', 'todo', 'in-progress', 'in-testing',
                                        'in-docs', 'in-review', 'needs-edits', 'done', 'cancelled'
                                    )),
    priority        TEXT            DEFAULT 'P2'
                                    CHECK (priority IN ('P0', 'P1', 'P2', 'P3', 'P4')),
    kind            TEXT            DEFAULT 'feature'
                                    CHECK (kind IN ('feature', 'bug', 'hotfix', 'chore', 'testcase')),
    assignee        TEXT            DEFAULT '',
    labels          JSONB           DEFAULT '[]',
    depends_on      JSONB           DEFAULT '[]',
    blocks          JSONB           DEFAULT '[]',
    estimate        TEXT            DEFAULT '',
    body            TEXT            DEFAULT '',
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_features_user_feature_id
    ON features (user_id, feature_id);
CREATE INDEX IF NOT EXISTS idx_features_project_slug ON features (project_slug);
CREATE INDEX IF NOT EXISTS idx_features_status       ON features (status);
CREATE INDEX IF NOT EXISTS idx_features_kind         ON features (kind);
CREATE INDEX IF NOT EXISTS idx_features_priority     ON features (priority);
CREATE INDEX IF NOT EXISTS idx_features_assignee     ON features (assignee);
CREATE INDEX IF NOT EXISTS idx_features_deleted_at   ON features (deleted_at);

COMMENT ON TABLE features IS 'Feature workflow items tracked through gated lifecycle';
COMMENT ON COLUMN features.feature_id IS 'Human-readable ID like FEAT-ABC (unique per user)';

-- =============================================================================
-- Plans
-- =============================================================================

CREATE TABLE IF NOT EXISTS plans (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id      UUID            REFERENCES projects(id) ON DELETE SET NULL,
    title           TEXT            NOT NULL,
    description     TEXT            DEFAULT '',
    body            TEXT            DEFAULT '',
    status          TEXT            DEFAULT 'draft'
                                    CHECK (status IN ('draft', 'approved', 'in-progress', 'completed', 'cancelled')),
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_plans_user_id    ON plans (user_id);
CREATE INDEX IF NOT EXISTS idx_plans_project_id ON plans (project_id);
CREATE INDEX IF NOT EXISTS idx_plans_status     ON plans (status);
CREATE INDEX IF NOT EXISTS idx_plans_deleted_at ON plans (deleted_at);

COMMENT ON TABLE plans IS 'Grouped feature delivery plans with approval workflow';

-- =============================================================================
-- Requests
-- =============================================================================

CREATE TABLE IF NOT EXISTS requests (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id      UUID            REFERENCES projects(id) ON DELETE SET NULL,
    title           TEXT            NOT NULL,
    description     TEXT            DEFAULT '',
    kind            TEXT            DEFAULT 'feature'
                                    CHECK (kind IN ('feature', 'bug', 'hotfix', 'chore')),
    status          TEXT            DEFAULT 'pending'
                                    CHECK (status IN ('pending', 'accepted', 'converted', 'dismissed')),
    priority        TEXT            DEFAULT 'P2'
                                    CHECK (priority IN ('P0', 'P1', 'P2', 'P3', 'P4')),
    body            TEXT            DEFAULT '',
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_requests_user_id    ON requests (user_id);
CREATE INDEX IF NOT EXISTS idx_requests_project_id ON requests (project_id);
CREATE INDEX IF NOT EXISTS idx_requests_status     ON requests (status);
CREATE INDEX IF NOT EXISTS idx_requests_deleted_at ON requests (deleted_at);

COMMENT ON TABLE requests IS 'Queued user requests that can be converted into features';

-- =============================================================================
-- Epics
-- =============================================================================

CREATE TABLE IF NOT EXISTS epics (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id      UUID            REFERENCES projects(id) ON DELETE SET NULL,
    title           TEXT            NOT NULL,
    description     TEXT            DEFAULT '',
    status          TEXT            DEFAULT 'open'
                                    CHECK (status IN ('open', 'in-progress', 'done', 'cancelled')),
    priority        TEXT            DEFAULT 'P2'
                                    CHECK (priority IN ('P0', 'P1', 'P2', 'P3', 'P4')),
    labels          JSONB           DEFAULT '[]',
    body            TEXT            DEFAULT '',
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_epics_user_id    ON epics (user_id);
CREATE INDEX IF NOT EXISTS idx_epics_project_id ON epics (project_id);
CREATE INDEX IF NOT EXISTS idx_epics_status     ON epics (status);
CREATE INDEX IF NOT EXISTS idx_epics_deleted_at ON epics (deleted_at);

COMMENT ON TABLE epics IS 'High-level grouping of related features and stories';

-- =============================================================================
-- Stories
-- =============================================================================

CREATE TABLE IF NOT EXISTS stories (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id      UUID            REFERENCES projects(id) ON DELETE SET NULL,
    epic_id         UUID            REFERENCES epics(id) ON DELETE SET NULL,
    title           TEXT            NOT NULL,
    description     TEXT            DEFAULT '',
    status          TEXT            DEFAULT 'open'
                                    CHECK (status IN ('open', 'in-progress', 'done', 'cancelled')),
    priority        TEXT            DEFAULT 'P2'
                                    CHECK (priority IN ('P0', 'P1', 'P2', 'P3', 'P4')),
    points          INTEGER         DEFAULT 0,
    assignee        TEXT            DEFAULT '',
    labels          JSONB           DEFAULT '[]',
    body            TEXT            DEFAULT '',
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_stories_user_id    ON stories (user_id);
CREATE INDEX IF NOT EXISTS idx_stories_project_id ON stories (project_id);
CREATE INDEX IF NOT EXISTS idx_stories_epic_id    ON stories (epic_id);
CREATE INDEX IF NOT EXISTS idx_stories_status     ON stories (status);
CREATE INDEX IF NOT EXISTS idx_stories_deleted_at ON stories (deleted_at);

COMMENT ON TABLE stories IS 'User stories within epics, with point estimates';

-- =============================================================================
-- Tasks
-- =============================================================================

CREATE TABLE IF NOT EXISTS tasks (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id      UUID            REFERENCES projects(id) ON DELETE SET NULL,
    story_id        UUID            REFERENCES stories(id) ON DELETE SET NULL,
    feature_id      UUID            REFERENCES features(id) ON DELETE SET NULL,
    title           TEXT            NOT NULL,
    description     TEXT            DEFAULT '',
    status          TEXT            DEFAULT 'open'
                                    CHECK (status IN ('open', 'in-progress', 'done', 'cancelled')),
    priority        TEXT            DEFAULT 'P2'
                                    CHECK (priority IN ('P0', 'P1', 'P2', 'P3', 'P4')),
    assignee        TEXT            DEFAULT '',
    labels          JSONB           DEFAULT '[]',
    body            TEXT            DEFAULT '',
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_tasks_user_id    ON tasks (user_id);
CREATE INDEX IF NOT EXISTS idx_tasks_project_id ON tasks (project_id);
CREATE INDEX IF NOT EXISTS idx_tasks_story_id   ON tasks (story_id);
CREATE INDEX IF NOT EXISTS idx_tasks_feature_id ON tasks (feature_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status     ON tasks (status);
CREATE INDEX IF NOT EXISTS idx_tasks_deleted_at ON tasks (deleted_at);

COMMENT ON TABLE tasks IS 'Granular work items within stories or features';
