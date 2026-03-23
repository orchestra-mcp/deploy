-- 011_create_api_collections.sql
-- API collections, endpoints, and environments.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- API Collections
-- =============================================================================

CREATE TABLE IF NOT EXISTS api_collections (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    team_id         UUID            REFERENCES teams(id) ON DELETE SET NULL,
    name            TEXT            NOT NULL,
    slug            TEXT            NOT NULL DEFAULT '',
    base_url        TEXT            DEFAULT '',
    description     TEXT            DEFAULT '',
    visibility      TEXT            DEFAULT 'private'
                                    CHECK (visibility IN ('private', 'team', 'public')),
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_api_collections_user_id    ON api_collections (user_id);
CREATE INDEX IF NOT EXISTS idx_api_collections_team_id    ON api_collections (team_id);
CREATE INDEX IF NOT EXISTS idx_api_collections_slug       ON api_collections (slug);
CREATE INDEX IF NOT EXISTS idx_api_collections_deleted_at ON api_collections (deleted_at);

COMMENT ON TABLE api_collections IS 'Grouped REST API endpoint collections (Postman-like)';

-- =============================================================================
-- API Endpoints
-- =============================================================================

CREATE TABLE IF NOT EXISTS api_endpoints (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id       UUID        NOT NULL REFERENCES api_collections(id) ON DELETE CASCADE,
    user_id             BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name                TEXT        NOT NULL DEFAULT '',
    method              TEXT        NOT NULL DEFAULT 'GET'
                                    CHECK (method IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS')),
    path                TEXT        NOT NULL DEFAULT '',
    description         TEXT        DEFAULT '',
    body                TEXT        DEFAULT '',
    headers             JSONB       DEFAULT '{}',
    request_example     TEXT        DEFAULT '',
    response_example    TEXT        DEFAULT '',
    version             INTEGER     DEFAULT 1,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_api_endpoints_collection_id ON api_endpoints (collection_id);
CREATE INDEX IF NOT EXISTS idx_api_endpoints_user_id       ON api_endpoints (user_id);
CREATE INDEX IF NOT EXISTS idx_api_endpoints_method        ON api_endpoints (method);

COMMENT ON TABLE api_endpoints IS 'Individual API endpoint definitions within a collection';

-- =============================================================================
-- API Environments
-- =============================================================================

CREATE TABLE IF NOT EXISTS api_environments (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id   UUID            NOT NULL REFERENCES api_collections(id) ON DELETE CASCADE,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            TEXT            NOT NULL DEFAULT '',
    variables       JSONB           DEFAULT '{}',
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_api_environments_collection_id ON api_environments (collection_id);
CREATE INDEX IF NOT EXISTS idx_api_environments_user_id       ON api_environments (user_id);

COMMENT ON TABLE api_environments IS 'Variable sets for API collections (dev, staging, prod)';
