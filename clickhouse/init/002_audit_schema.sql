-- 002_audit_schema.sql
-- Audit log archive in ClickHouse for long-term storage and analytics.
-- PostgreSQL audit.log entries are forwarded here periodically for retention
-- beyond the 90-day PostgreSQL cleanup window.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Audit Log Archive Table
-- =============================================================================
-- Mirrors the PostgreSQL audit.log schema with ClickHouse-native types.
-- Partitioned by month, ordered for efficient querying by table + user + time.
-- 2-year TTL (730 days) — after which rows are automatically dropped.

CREATE TABLE IF NOT EXISTS orchestra_analytics.audit_log (
    id              UInt64,
    action          String,
    schema_name     String,
    table_name      String,
    user_id         String      DEFAULT '',
    user_role       String      DEFAULT '',
    session_id      String      DEFAULT '',
    record_id       String      DEFAULT '',
    old_data        String      DEFAULT '{}',       -- JSON string of previous row state
    new_data        String      DEFAULT '{}',       -- JSON string of new row state
    changed_fields  Array(String) DEFAULT [],        -- Columns that changed (UPDATE only)
    client_ip       String      DEFAULT '',
    user_agent      String      DEFAULT '',
    statement_only  UInt8       DEFAULT 0,           -- 1 = statement-level (TRUNCATE)
    logged_at       DateTime64(3)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(logged_at)
ORDER BY (table_name, user_id, logged_at)
TTL logged_at + INTERVAL 730 DAY;                   -- 2-year retention


-- =============================================================================
-- Materialized View: Daily Audit Summary
-- =============================================================================
-- Pre-aggregated daily counts of changes per table and action type.
-- Useful for dashboards, compliance reports, and anomaly detection.

CREATE MATERIALIZED VIEW IF NOT EXISTS orchestra_analytics.daily_audit_summary
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(day)
ORDER BY (day, table_name, action)
AS SELECT
    toDate(logged_at)       AS day,
    table_name,
    action,
    count()                 AS change_count,
    uniqExact(user_id)      AS unique_users
FROM orchestra_analytics.audit_log
GROUP BY day, table_name, action;
