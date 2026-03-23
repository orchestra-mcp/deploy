-- 009_create_sessions.sql
-- AI sessions, turns, delegations, persons, and assignment rules.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- AI Sessions
-- =============================================================================

CREATE TABLE IF NOT EXISTS ai_sessions (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id      UUID            REFERENCES projects(id) ON DELETE SET NULL,
    name            TEXT            NOT NULL DEFAULT '',
    model           TEXT            DEFAULT '',
    pinned          BOOLEAN         DEFAULT false,
    last_message_at TIMESTAMPTZ,
    message_count   INTEGER         DEFAULT 0,
    meta            JSONB           DEFAULT '{}',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_ai_sessions_user_id        ON ai_sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_ai_sessions_project_id     ON ai_sessions (project_id);
CREATE INDEX IF NOT EXISTS idx_ai_sessions_pinned         ON ai_sessions (pinned) WHERE pinned = true;
CREATE INDEX IF NOT EXISTS idx_ai_sessions_last_message_at ON ai_sessions (last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_sessions_deleted_at     ON ai_sessions (deleted_at);

COMMENT ON TABLE ai_sessions IS 'AI chat sessions with model and message tracking';

-- =============================================================================
-- Session Turns
-- =============================================================================

CREATE TABLE IF NOT EXISTS session_turns (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID            NOT NULL REFERENCES ai_sessions(id) ON DELETE CASCADE,
    role            TEXT            NOT NULL
                                    CHECK (role IN ('user', 'assistant', 'system', 'tool')),
    content         TEXT            NOT NULL DEFAULT '',
    tool_calls      JSONB           DEFAULT NULL,
    model           TEXT            DEFAULT '',
    tokens_in       INTEGER         DEFAULT 0,
    tokens_out      INTEGER         DEFAULT 0,
    processed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_session_turns_session_id  ON session_turns (session_id);
CREATE INDEX IF NOT EXISTS idx_session_turns_created_at  ON session_turns (session_id, created_at);

COMMENT ON TABLE session_turns IS 'Individual messages within an AI session';
COMMENT ON COLUMN session_turns.role IS 'One of: user, assistant, system, tool';

-- =============================================================================
-- Persons (project team members / assignees)
-- =============================================================================

CREATE TABLE IF NOT EXISTS persons (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          REFERENCES users(id) ON DELETE SET NULL,
    project_id      UUID            REFERENCES projects(id) ON DELETE SET NULL,
    name            TEXT            NOT NULL DEFAULT '',
    email           TEXT            DEFAULT '',
    role            TEXT            DEFAULT 'developer'
                                    CHECK (role IN ('developer', 'designer', 'qa', 'pm', 'lead', 'admin')),
    bio             TEXT            DEFAULT '',
    status          TEXT            DEFAULT 'active'
                                    CHECK (status IN ('active', 'away', 'inactive')),
    integrations    JSONB           DEFAULT '{}',
    labels          JSONB           DEFAULT '[]',
    github_email    TEXT            DEFAULT '',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_persons_user_id    ON persons (user_id);
CREATE INDEX IF NOT EXISTS idx_persons_project_id ON persons (project_id);
CREATE INDEX IF NOT EXISTS idx_persons_status     ON persons (status);
CREATE INDEX IF NOT EXISTS idx_persons_deleted_at ON persons (deleted_at);

COMMENT ON TABLE persons IS 'Project team member profiles used for feature assignment';

-- =============================================================================
-- Delegations
-- =============================================================================

CREATE TABLE IF NOT EXISTS delegations (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id      UUID            REFERENCES projects(id) ON DELETE SET NULL,
    feature_id      UUID            REFERENCES features(id) ON DELETE SET NULL,
    from_person_id  UUID            REFERENCES persons(id) ON DELETE SET NULL,
    to_person_id    UUID            REFERENCES persons(id) ON DELETE SET NULL,
    context         TEXT            DEFAULT '',
    question        TEXT            DEFAULT '',
    response        TEXT            DEFAULT '',
    responded_at    TIMESTAMPTZ,
    status          TEXT            DEFAULT 'pending'
                                    CHECK (status IN ('pending', 'accepted', 'rejected', 'completed')),
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_delegations_user_id        ON delegations (user_id);
CREATE INDEX IF NOT EXISTS idx_delegations_feature_id     ON delegations (feature_id);
CREATE INDEX IF NOT EXISTS idx_delegations_from_person_id ON delegations (from_person_id);
CREATE INDEX IF NOT EXISTS idx_delegations_to_person_id   ON delegations (to_person_id);
CREATE INDEX IF NOT EXISTS idx_delegations_status         ON delegations (status);

COMMENT ON TABLE delegations IS 'Feature work delegation requests between team members';

-- =============================================================================
-- Assignment Rules
-- =============================================================================

CREATE TABLE IF NOT EXISTS assignment_rules (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id          UUID        REFERENCES projects(id) ON DELETE CASCADE,
    kind                TEXT        NOT NULL
                                    CHECK (kind IN ('feature', 'bug', 'hotfix', 'chore', 'testcase')),
    assignee_person_id  UUID        REFERENCES persons(id) ON DELETE CASCADE,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_assignment_rules_project_id ON assignment_rules (project_id);
CREATE INDEX IF NOT EXISTS idx_assignment_rules_kind       ON assignment_rules (kind);

COMMENT ON TABLE assignment_rules IS 'Auto-assignment rules mapping feature kinds to persons';
