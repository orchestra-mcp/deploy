-- =============================================================================
-- 000b_supabase_logging.sql — Supabase logging + ClickHouse integration
-- =============================================================================
-- Supabase's Logflare/Analytics uses the _analytics schema.
-- We also create a logging pipeline that can forward to ClickHouse.
-- =============================================================================

-- ── Supabase internal logging (for Logflare/Analytics integration) ──

-- API request logs (stored in PG, optionally forwarded to ClickHouse)
CREATE TABLE IF NOT EXISTS _analytics.api_request_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    method TEXT,
    path TEXT,
    status_code INTEGER,
    user_id TEXT DEFAULT '',
    ip_address TEXT DEFAULT '',
    user_agent TEXT DEFAULT '',
    request_body_size INTEGER DEFAULT 0,
    response_body_size INTEGER DEFAULT 0,
    duration_ms INTEGER DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_api_request_logs_timestamp
    ON _analytics.api_request_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_api_request_logs_path
    ON _analytics.api_request_logs(path, timestamp);

-- Auth event logs
CREATE TABLE IF NOT EXISTS _analytics.auth_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type TEXT NOT NULL,  -- signup, login, logout, token_refresh, password_reset, etc.
    user_id TEXT DEFAULT '',
    provider TEXT DEFAULT '',  -- email, google, github, etc.
    ip_address TEXT DEFAULT '',
    user_agent TEXT DEFAULT '',
    success BOOLEAN DEFAULT true,
    error TEXT DEFAULT '',
    metadata JSONB DEFAULT '{}',
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auth_events_timestamp
    ON _analytics.auth_events(timestamp);
CREATE INDEX IF NOT EXISTS idx_auth_events_type
    ON _analytics.auth_events(event_type, timestamp);
CREATE INDEX IF NOT EXISTS idx_auth_events_user
    ON _analytics.auth_events(user_id, timestamp);

-- Edge function invocation logs
CREATE TABLE IF NOT EXISTS _analytics.edge_function_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    function_name TEXT NOT NULL,
    method TEXT DEFAULT '',
    status_code INTEGER DEFAULT 200,
    duration_ms INTEGER DEFAULT 0,
    memory_used_mb FLOAT DEFAULT 0,
    user_id TEXT DEFAULT '',
    error TEXT DEFAULT '',
    metadata JSONB DEFAULT '{}',
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_edge_function_logs_timestamp
    ON _analytics.edge_function_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_edge_function_logs_function
    ON _analytics.edge_function_logs(function_name, timestamp);

-- Realtime connection logs
CREATE TABLE IF NOT EXISTS _analytics.realtime_connection_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel TEXT NOT NULL,
    event_type TEXT NOT NULL,  -- join, leave, broadcast, presence
    user_id TEXT DEFAULT '',
    duration_ms INTEGER DEFAULT 0,
    messages_count INTEGER DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_realtime_logs_timestamp
    ON _analytics.realtime_connection_logs(timestamp);

-- Storage access logs
CREATE TABLE IF NOT EXISTS _analytics.storage_access_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    operation TEXT NOT NULL,  -- upload, download, delete, list
    bucket_id TEXT DEFAULT '',
    object_path TEXT DEFAULT '',
    file_size_bytes BIGINT DEFAULT 0,
    user_id TEXT DEFAULT '',
    duration_ms INTEGER DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_storage_logs_timestamp
    ON _analytics.storage_access_logs(timestamp);

-- Grant analytics schema access to service_role
GRANT USAGE ON SCHEMA _analytics TO service_role, postgres;
GRANT ALL ON ALL TABLES IN SCHEMA _analytics TO service_role, postgres;
GRANT ALL ON ALL SEQUENCES IN SCHEMA _analytics TO service_role, postgres;

COMMENT ON SCHEMA _analytics IS 'Supabase analytics and logging tables. PG is short-term store; ClickHouse is long-term analytics.';
