-- 015_create_tunnels.sql
-- Tunnels, sharing, sync logs, action logs, event logs, notifications, packs,
-- repo workspaces, and all operational tables.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Tunnels
-- =============================================================================

CREATE TABLE IF NOT EXISTS tunnels (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    team_id             UUID        REFERENCES teams(id) ON DELETE SET NULL,
    name                TEXT        NOT NULL DEFAULT '',
    hostname            TEXT        DEFAULT '',
    os                  TEXT        DEFAULT '',
    architecture        TEXT        DEFAULT '',
    gate_address        TEXT        DEFAULT '',
    connection_token    TEXT        DEFAULT '',
    status              TEXT        DEFAULT 'offline'
                                    CHECK (status IN ('online', 'offline', 'connecting', 'error')),
    last_seen_at        TIMESTAMPTZ,
    labels              JSONB       DEFAULT '[]',
    meta                JSONB       DEFAULT '{}',
    version             INTEGER     DEFAULT 1,
    tool_count          INTEGER     DEFAULT 0,
    local_ip            TEXT        DEFAULT '',
    workspace           TEXT        DEFAULT '',
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_tunnels_user_id    ON tunnels (user_id);
CREATE INDEX IF NOT EXISTS idx_tunnels_team_id    ON tunnels (team_id);
CREATE INDEX IF NOT EXISTS idx_tunnels_status     ON tunnels (status);
CREATE INDEX IF NOT EXISTS idx_tunnels_deleted_at ON tunnels (deleted_at);

COMMENT ON TABLE tunnels IS 'Registered machine tunnels for remote MCP tool access';

-- =============================================================================
-- Shared Contents
-- =============================================================================

CREATE TABLE IF NOT EXISTS shared_contents (
    id              BIGSERIAL       PRIMARY KEY,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entity_type     TEXT            NOT NULL DEFAULT '',
    entity_id       UUID            NOT NULL,
    slug            TEXT            NOT NULL DEFAULT '',
    title           TEXT            DEFAULT '',
    description     TEXT            DEFAULT '',
    content         TEXT            DEFAULT '',
    visibility      TEXT            DEFAULT 'public'
                                    CHECK (visibility IN ('public', 'unlisted', 'password', 'private')),
    views_count     INTEGER         DEFAULT 0,
    likes_count     INTEGER         DEFAULT 0,
    unique_views    INTEGER         DEFAULT 0,
    password        TEXT            DEFAULT '',
    team_id         UUID            REFERENCES teams(id) ON DELETE SET NULL,
    custom_domain   TEXT            DEFAULT '',
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shared_contents_user_id     ON shared_contents (user_id);
CREATE INDEX IF NOT EXISTS idx_shared_contents_slug        ON shared_contents (slug);
CREATE INDEX IF NOT EXISTS idx_shared_contents_entity      ON shared_contents (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_shared_contents_visibility  ON shared_contents (visibility);

COMMENT ON TABLE shared_contents IS 'Publicly shared content with view tracking and access control';

-- =============================================================================
-- Share Comments
-- =============================================================================

CREATE TABLE IF NOT EXISTS share_comments (
    id              BIGSERIAL       PRIMARY KEY,
    share_id        BIGINT          NOT NULL REFERENCES shared_contents(id) ON DELETE CASCADE,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body            TEXT            DEFAULT '',
    kind            TEXT            DEFAULT 'comment'
                                    CHECK (kind IN ('comment', 'reply', 'reaction')),
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_share_comments_share_id ON share_comments (share_id);
CREATE INDEX IF NOT EXISTS idx_share_comments_user_id  ON share_comments (user_id);

COMMENT ON TABLE share_comments IS 'Comments on publicly shared content';

-- =============================================================================
-- Team Shares
-- =============================================================================

CREATE TABLE IF NOT EXISTS team_shares (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    team_id         UUID            NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    entity_type     TEXT            NOT NULL DEFAULT '',
    entity_id       TEXT            NOT NULL DEFAULT '',
    share_with_all  BOOLEAN         DEFAULT false,
    member_ids      JSONB           DEFAULT '[]',
    permission      TEXT            DEFAULT 'read'
                                    CHECK (permission IN ('read', 'write', 'admin')),
    content_hash    TEXT            DEFAULT '',
    entity_data     JSONB           DEFAULT '{}',
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_team_shares_user_id    ON team_shares (user_id);
CREATE INDEX IF NOT EXISTS idx_team_shares_team_id    ON team_shares (team_id);
CREATE INDEX IF NOT EXISTS idx_team_shares_entity     ON team_shares (entity_type, entity_id);

COMMENT ON TABLE team_shares IS 'Intra-team content sharing with permission levels';

-- =============================================================================
-- Content Views (analytics)
-- =============================================================================

CREATE TABLE IF NOT EXISTS content_views (
    id              BIGSERIAL       PRIMARY KEY,
    content_id      BIGINT          NOT NULL REFERENCES shared_contents(id) ON DELETE CASCADE,
    viewer_hash     TEXT            DEFAULT '',
    user_agent      TEXT            DEFAULT '',
    referer         TEXT            DEFAULT '',
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_content_views_content_id ON content_views (content_id);
CREATE INDEX IF NOT EXISTS idx_content_views_created_at ON content_views (created_at);

COMMENT ON TABLE content_views IS 'Anonymous view tracking for shared content analytics';

-- =============================================================================
-- Custom Domains
-- =============================================================================

CREATE TABLE IF NOT EXISTS custom_domains (
    id              BIGSERIAL       PRIMARY KEY,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    domain          TEXT            UNIQUE NOT NULL,
    verified        BOOLEAN         DEFAULT false,
    dns_txt_record  TEXT            DEFAULT '',
    verified_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_custom_domains_user_id ON custom_domains (user_id);
CREATE INDEX IF NOT EXISTS idx_custom_domains_domain  ON custom_domains (domain);

COMMENT ON TABLE custom_domains IS 'User-owned custom domains for shared content';

-- =============================================================================
-- Action Histories
-- =============================================================================

CREATE TABLE IF NOT EXISTS action_histories (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    tunnel_id       UUID            REFERENCES tunnels(id) ON DELETE SET NULL,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    action_type     TEXT            NOT NULL DEFAULT '',
    tool_name       TEXT            DEFAULT '',
    status          TEXT            DEFAULT 'pending'
                                    CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
    attempted_at    TIMESTAMPTZ     DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    error           TEXT            DEFAULT '',
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_action_histories_tunnel_id ON action_histories (tunnel_id);
CREATE INDEX IF NOT EXISTS idx_action_histories_user_id   ON action_histories (user_id);
CREATE INDEX IF NOT EXISTS idx_action_histories_status    ON action_histories (status);

COMMENT ON TABLE action_histories IS 'Audit trail of tunnel tool invocations';

-- =============================================================================
-- Action Logs (detailed)
-- =============================================================================

CREATE TABLE IF NOT EXISTS action_logs (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tunnel_id       UUID            REFERENCES tunnels(id) ON DELETE SET NULL,
    action_type     TEXT            NOT NULL DEFAULT '',
    tool_name       TEXT            DEFAULT '',
    params          JSONB           DEFAULT '{}',
    output          TEXT            DEFAULT '',
    files           JSONB           DEFAULT '[]',
    progress        JSONB           DEFAULT '{}',
    success         BOOLEAN         DEFAULT false,
    duration_ms     INTEGER         DEFAULT 0,
    error           TEXT            DEFAULT '',
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_action_logs_user_id   ON action_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_action_logs_tunnel_id ON action_logs (tunnel_id);
CREATE INDEX IF NOT EXISTS idx_action_logs_tool_name ON action_logs (tool_name);
CREATE INDEX IF NOT EXISTS idx_action_logs_created   ON action_logs (created_at);

COMMENT ON TABLE action_logs IS 'Detailed execution logs for tunnel actions with params and output';

-- =============================================================================
-- MCP Event Logs
-- =============================================================================

CREATE TABLE IF NOT EXISTS mcp_event_logs (
    id              BIGSERIAL       PRIMARY KEY,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type      TEXT            NOT NULL DEFAULT '',
    session_id      TEXT            DEFAULT '',
    tool_name       TEXT            DEFAULT '',
    agent_type      TEXT            DEFAULT '',
    data            JSONB           DEFAULT '{}',
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mcp_event_logs_user_id    ON mcp_event_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_mcp_event_logs_event_type ON mcp_event_logs (event_type);
CREATE INDEX IF NOT EXISTS idx_mcp_event_logs_session_id ON mcp_event_logs (session_id);
CREATE INDEX IF NOT EXISTS idx_mcp_event_logs_created    ON mcp_event_logs (created_at);

COMMENT ON TABLE mcp_event_logs IS 'MCP protocol event stream for observability and debugging';

-- =============================================================================
-- Sync Logs
-- =============================================================================

CREATE TABLE IF NOT EXISTS sync_logs (
    id              BIGSERIAL       PRIMARY KEY,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_slug    TEXT            NOT NULL DEFAULT '',
    status          TEXT            DEFAULT 'started'
                                    CHECK (status IN ('started', 'completed', 'failed', 'conflict')),
    error_message   TEXT            DEFAULT '',
    conflict_count  INTEGER         DEFAULT 0,
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sync_logs_user_id      ON sync_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_sync_logs_project_slug ON sync_logs (project_slug);
CREATE INDEX IF NOT EXISTS idx_sync_logs_status       ON sync_logs (status);

COMMENT ON TABLE sync_logs IS 'Data sync operation history per project';

-- =============================================================================
-- Conflict Logs
-- =============================================================================

CREATE TABLE IF NOT EXISTS conflict_logs (
    id              BIGSERIAL       PRIMARY KEY,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_slug    TEXT            NOT NULL DEFAULT '',
    conflict_type   TEXT            NOT NULL DEFAULT '',
    local_version   INTEGER         DEFAULT 0,
    remote_version  INTEGER         DEFAULT 0,
    entity_type     TEXT            DEFAULT '',
    entity_id       TEXT            DEFAULT '',
    details         JSONB           DEFAULT '{}',
    resolved        BOOLEAN         DEFAULT false,
    resolved_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_conflict_logs_user_id      ON conflict_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_conflict_logs_project_slug ON conflict_logs (project_slug);
CREATE INDEX IF NOT EXISTS idx_conflict_logs_resolved     ON conflict_logs (resolved) WHERE resolved = false;

COMMENT ON TABLE conflict_logs IS 'Sync conflict records with resolution tracking';

-- =============================================================================
-- Repo Workspaces (code indexing)
-- =============================================================================

CREATE TABLE IF NOT EXISTS repo_workspaces (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    team_id             UUID        REFERENCES teams(id) ON DELETE SET NULL,
    name                TEXT        NOT NULL DEFAULT '',
    root_path           TEXT        DEFAULT '',
    language            TEXT        DEFAULT '',
    last_indexed_at     TIMESTAMPTZ,
    file_count          INTEGER     DEFAULT 0,
    indexed_symbols     INTEGER     DEFAULT 0,
    version             INTEGER     DEFAULT 1,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_repo_workspaces_user_id    ON repo_workspaces (user_id);
CREATE INDEX IF NOT EXISTS idx_repo_workspaces_team_id    ON repo_workspaces (team_id);
CREATE INDEX IF NOT EXISTS idx_repo_workspaces_deleted_at ON repo_workspaces (deleted_at);

COMMENT ON TABLE repo_workspaces IS 'Indexed code repositories for search and RAG';

-- =============================================================================
-- Notifications
-- =============================================================================

CREATE TABLE IF NOT EXISTS notifications (
    id              BIGSERIAL       PRIMARY KEY,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title           TEXT            NOT NULL DEFAULT '',
    message         TEXT            DEFAULT '',
    type            TEXT            DEFAULT 'info'
                                    CHECK (type IN ('info', 'success', 'warning', 'error', 'action')),
    read_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id    ON notifications (user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_read_at    ON notifications (read_at) WHERE read_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_type       ON notifications (type);
CREATE INDEX IF NOT EXISTS idx_notifications_deleted_at ON notifications (deleted_at);

COMMENT ON TABLE notifications IS 'In-app user notifications with read tracking';

-- =============================================================================
-- Packs (marketplace registry)
-- =============================================================================

CREATE TABLE IF NOT EXISTS packs (
    name            TEXT            PRIMARY KEY,
    version         TEXT            NOT NULL DEFAULT '0.0.0',
    repo            TEXT            DEFAULT '',
    installed_at    TIMESTAMPTZ     DEFAULT NOW(),
    metadata        JSONB           DEFAULT '{}'
);

COMMENT ON TABLE packs IS 'Installed marketplace pack registry';
