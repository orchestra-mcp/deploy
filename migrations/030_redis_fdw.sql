-- =============================================================================
-- Redis Foreign Data Wrapper (via Supabase Wrappers extension)
--
-- Exposes Redis key namespaces as queryable foreign tables in Postgres.
-- Requires: wrappers extension + supabase_vault (pre-installed)
-- Requires: Redis container running on same Docker network
--
-- The Redis connection URL is stored in Supabase Vault.
-- On first deploy, the secret is created and its ID stored for reuse.
-- Safe to re-run (idempotent).
-- =============================================================================

-- ── Ensure extensions are enabled ────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS wrappers WITH SCHEMA extensions;

-- ── Create the Redis FDW ─────────────────────────────────────────────────────

DO $$ BEGIN
    CREATE FOREIGN DATA WRAPPER redis_wrapper
        HANDLER extensions.redis_fdw_handler
        VALIDATOR extensions.redis_fdw_validator;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── Store Redis URL in Vault (idempotent) ────────────────────────────────────
-- psql -v redis_password=<pass> injects the value here as a plain SQL literal.
-- We use a CTE to upsert: delete existing + recreate to keep it idempotent.

SELECT vault.update_secret(id, 'redis://:' || :'redis_password' || '@redis:6379')
FROM vault.secrets WHERE name = 'redis_conn_url';

-- If no row was updated (secret doesn't exist yet), create it
INSERT INTO vault.secrets (secret, name, description)
SELECT 'redis://:' || :'redis_password' || '@redis:6379', 'redis_conn_url', 'Redis connection URL for FDW'
WHERE NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'redis_conn_url');

-- ── Drop and recreate Redis server using Vault secret ────────────────────────

DROP SERVER IF EXISTS redis_server CASCADE;

DO $$
DECLARE
    v_secret_id uuid;
    v_sql text;
BEGIN
    SELECT id INTO v_secret_id FROM vault.secrets WHERE name = 'redis_conn_url' LIMIT 1;
    IF v_secret_id IS NULL THEN
        RAISE EXCEPTION 'Vault secret redis_conn_url not found';
    END IF;
    v_sql := format(
        $q$CREATE SERVER redis_server FOREIGN DATA WRAPPER redis_wrapper OPTIONS (conn_url_id '%s')$q$,
        v_secret_id
    );
    EXECUTE v_sql;
    RAISE NOTICE 'Created server: redis_server (secret=%)', v_secret_id;
END $$;

-- ── Foreign Tables ───────────────────────────────────────────────────────────

-- Session store (hash keys matching: session:*)
CREATE FOREIGN TABLE IF NOT EXISTS public.redis_sessions (
    key   text,
    field text,
    value text
)
SERVER redis_server
OPTIONS (src_type 'hash', src_key 'session:*');

-- Feature flag evaluation cache (hash keys: feature:*)
CREATE FOREIGN TABLE IF NOT EXISTS public.redis_feature_flags (
    key   text,
    field text,
    value text
)
SERVER redis_server
OPTIONS (src_type 'hash', src_key 'feature:*');

-- Rate limit counters (hash keys: ratelimit:*)
CREATE FOREIGN TABLE IF NOT EXISTS public.redis_rate_limits (
    key   text,
    field text,
    value text
)
SERVER redis_server
OPTIONS (src_type 'hash', src_key 'ratelimit:*');

-- MCP session state (hash keys: mcp:session:*)
CREATE FOREIGN TABLE IF NOT EXISTS public.redis_mcp_sessions (
    key   text,
    field text,
    value text
)
SERVER redis_server
OPTIONS (src_type 'hash', src_key 'mcp:session:*');

-- ── Grants ────────────────────────────────────────────────────────────────────

GRANT SELECT ON public.redis_sessions TO service_role;
GRANT SELECT ON public.redis_feature_flags TO anon, authenticated, service_role;
GRANT SELECT ON public.redis_rate_limits TO service_role;
GRANT SELECT ON public.redis_mcp_sessions TO service_role;
