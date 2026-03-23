-- Analytics events (main event stream)
CREATE TABLE IF NOT EXISTS orchestra_analytics.events (
    event_id UUID DEFAULT generateUUIDv4(),
    user_id String,
    session_id String DEFAULT '',
    event_type String,
    event_name String,
    properties String DEFAULT '{}',  -- JSON string
    page_url String DEFAULT '',
    referrer String DEFAULT '',
    user_agent String DEFAULT '',
    ip_hash String DEFAULT '',  -- SHA-256 hashed IP
    country String DEFAULT '',
    device_type String DEFAULT '',
    browser String DEFAULT '',
    os String DEFAULT '',
    created_at DateTime64(3) DEFAULT now64(3)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(created_at)
ORDER BY (event_type, user_id, created_at)
TTL created_at + INTERVAL 365 DAY;

-- Page views (optimized for page analytics)
CREATE TABLE IF NOT EXISTS orchestra_analytics.page_views (
    view_id UUID DEFAULT generateUUIDv4(),
    user_id String DEFAULT '',
    session_id String DEFAULT '',
    page_url String,
    page_title String DEFAULT '',
    referrer String DEFAULT '',
    duration_ms UInt32 DEFAULT 0,
    scroll_depth Float32 DEFAULT 0,
    ip_hash String DEFAULT '',
    country String DEFAULT '',
    device_type String DEFAULT '',
    browser String DEFAULT '',
    created_at DateTime64(3) DEFAULT now64(3)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(created_at)
ORDER BY (page_url, created_at)
TTL created_at + INTERVAL 365 DAY;

-- Feature flag events (for A/B test tracking)
CREATE TABLE IF NOT EXISTS orchestra_analytics.feature_flag_events (
    event_id UUID DEFAULT generateUUIDv4(),
    user_id String,
    flag_key String,
    variant String DEFAULT 'control',
    context String DEFAULT '{}',
    created_at DateTime64(3) DEFAULT now64(3)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(created_at)
ORDER BY (flag_key, user_id, created_at)
TTL created_at + INTERVAL 365 DAY;

-- A/B test conversions
CREATE TABLE IF NOT EXISTS orchestra_analytics.ab_conversions (
    conversion_id UUID DEFAULT generateUUIDv4(),
    user_id String,
    experiment_id String,
    variant String,
    goal_name String,
    value Float64 DEFAULT 0,
    created_at DateTime64(3) DEFAULT now64(3)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(created_at)
ORDER BY (experiment_id, variant, created_at)
TTL created_at + INTERVAL 365 DAY;

-- MCP tool usage analytics
CREATE TABLE IF NOT EXISTS orchestra_analytics.mcp_tool_usage (
    event_id UUID DEFAULT generateUUIDv4(),
    user_id String,
    session_id String DEFAULT '',
    tool_name String,
    duration_ms UInt32 DEFAULT 0,
    success UInt8 DEFAULT 1,
    error String DEFAULT '',
    tokens_in UInt32 DEFAULT 0,
    tokens_out UInt32 DEFAULT 0,
    cost_usd Float64 DEFAULT 0,
    created_at DateTime64(3) DEFAULT now64(3)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(created_at)
ORDER BY (tool_name, user_id, created_at)
TTL created_at + INTERVAL 365 DAY;

-- Materialized view: daily event counts per type
CREATE MATERIALIZED VIEW IF NOT EXISTS orchestra_analytics.daily_event_counts
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(day)
ORDER BY (day, event_type)
AS SELECT
    toDate(created_at) AS day,
    event_type,
    count() AS event_count,
    uniqExact(user_id) AS unique_users
FROM orchestra_analytics.events
GROUP BY day, event_type;

-- Materialized view: daily page view counts
CREATE MATERIALIZED VIEW IF NOT EXISTS orchestra_analytics.daily_page_views
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(day)
ORDER BY (day, page_url)
AS SELECT
    toDate(created_at) AS day,
    page_url,
    count() AS view_count,
    uniqExact(CASE WHEN user_id != '' THEN user_id ELSE ip_hash END) AS unique_visitors,
    avg(duration_ms) AS avg_duration_ms
FROM orchestra_analytics.page_views
GROUP BY day, page_url;
