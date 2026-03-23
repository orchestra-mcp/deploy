-- =============================================================================
-- ClickHouse Foreign Data Wrapper (via Supabase Wrappers extension)
--
-- Creates foreign tables in Postgres that query ClickHouse directly.
-- Requires: wrappers extension (pre-installed in supabase/postgres image)
-- Requires: ClickHouse container running on same Docker network
--
-- Credentials injected via psql -v ch_conn_string="tcp://user:pass@host:9000/db"
-- Safe to re-run (idempotent).
-- =============================================================================

-- ── Enable wrappers extension ────────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS wrappers WITH SCHEMA extensions;

-- ── Create the ClickHouse FDW ────────────────────────────────────────────────

DO $$ BEGIN
    CREATE FOREIGN DATA WRAPPER click_house_wrapper
        HANDLER extensions.click_house_fdw_handler
        VALIDATOR extensions.click_house_fdw_validator;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── Drop old server names from manual setup ──────────────────────────────────

DROP SERVER IF EXISTS events_server CASCADE;
DROP SERVER IF EXISTS clickhouse_server CASCADE;

-- ── Create the ClickHouse server with credentials ────────────────────────────
-- psql variable :ch_conn_string is interpolated here (not inside DO $$)

CREATE SERVER clickhouse_server
    FOREIGN DATA WRAPPER click_house_wrapper
    OPTIONS (conn_string :'ch_conn_string');

-- ── Foreign Tables ───────────────────────────────────────────────────────────

CREATE FOREIGN TABLE IF NOT EXISTS public.ch_events (
    event_id    text,
    user_id     text,
    session_id  text,
    event_type  text,
    event_name  text,
    properties  text,
    page_url    text,
    referrer    text,
    user_agent  text,
    ip_hash     text,
    country     text,
    device_type text,
    browser     text,
    os          text,
    created_at  timestamp
)
SERVER clickhouse_server
OPTIONS (table 'events', rowid_column 'event_id');

CREATE FOREIGN TABLE IF NOT EXISTS public.ch_page_views (
    view_id      text,
    user_id      text,
    session_id   text,
    page_url     text,
    page_title   text,
    referrer     text,
    duration_ms  bigint,
    scroll_depth real,
    ip_hash      text,
    country      text,
    device_type  text,
    browser      text,
    created_at   timestamp
)
SERVER clickhouse_server
OPTIONS (table 'page_views', rowid_column 'view_id');

CREATE FOREIGN TABLE IF NOT EXISTS public.ch_mcp_tool_usage (
    event_id    text,
    user_id     text,
    session_id  text,
    tool_name   text,
    duration_ms bigint,
    success     smallint,
    error       text,
    tokens_in   bigint,
    tokens_out  bigint,
    cost_usd    double precision,
    created_at  timestamp
)
SERVER clickhouse_server
OPTIONS (table 'mcp_tool_usage', rowid_column 'event_id');

CREATE FOREIGN TABLE IF NOT EXISTS public.ch_feature_flag_events (
    event_id   text,
    user_id    text,
    flag_key   text,
    variant    text,
    context    text,
    created_at timestamp
)
SERVER clickhouse_server
OPTIONS (table 'feature_flag_events', rowid_column 'event_id');

CREATE FOREIGN TABLE IF NOT EXISTS public.ch_ab_conversions (
    conversion_id text,
    user_id       text,
    experiment_id text,
    variant       text,
    goal_name     text,
    value         double precision,
    created_at    timestamp
)
SERVER clickhouse_server
OPTIONS (table 'ab_conversions', rowid_column 'conversion_id');

CREATE FOREIGN TABLE IF NOT EXISTS public.ch_audit_log (
    id             bigint,
    action         text,
    schema_name    text,
    table_name     text,
    user_id        text,
    user_role      text,
    session_id     text,
    record_id      text,
    old_data       text,
    new_data       text,
    client_ip      text,
    user_agent     text,
    statement_only smallint,
    logged_at      timestamp
)
SERVER clickhouse_server
OPTIONS (table 'audit_log', rowid_column 'id');

-- ── Grants ────────────────────────────────────────────────────────────────────

GRANT SELECT ON public.ch_events TO anon, authenticated, service_role;
GRANT SELECT ON public.ch_page_views TO anon, authenticated, service_role;
GRANT SELECT ON public.ch_mcp_tool_usage TO anon, authenticated, service_role;
GRANT SELECT ON public.ch_feature_flag_events TO anon, authenticated, service_role;
GRANT SELECT ON public.ch_ab_conversions TO anon, authenticated, service_role;
GRANT SELECT ON public.ch_audit_log TO anon, authenticated, service_role;
