-- =============================================================================
-- 000_supabase_init.sql — Additional Supabase setup
-- =============================================================================
-- The supabase/postgres image (via its internal migrate.sh) already creates:
--   - All roles: anon, authenticated, service_role, authenticator,
--     supabase_auth_admin, supabase_storage_admin, supabase_functions_admin,
--     supabase_admin, dashboard_user, pgbouncer, postgres
--   - All schemas: auth, storage, extensions
--   - Core extensions: uuid-ossp, pgcrypto
--   - Auth tables and functions (auth.uid(), auth.role(), auth.email())
--   - PUBLICATION supabase_realtime
--
-- Passwords are set by 99-run-migrations.sh (which runs AFTER this file).
--
-- This file only adds things the image does NOT provide.
-- =============================================================================

-- ── 1. Additional extensions ──
-- pgjwt is not installed by the image but needed for custom JWT operations
DO $$ BEGIN
    CREATE EXTENSION IF NOT EXISTS pgjwt WITH SCHEMA extensions;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pgjwt extension not available: %', SQLERRM;
END $$;

-- pg_stat_statements for query analytics
DO $$ BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_stat_statements not available: %', SQLERRM;
END $$;

-- ── 2. Additional schemas (not created by the image) ──
CREATE SCHEMA IF NOT EXISTS _realtime;
CREATE SCHEMA IF NOT EXISTS _analytics;
CREATE SCHEMA IF NOT EXISTS graphql_public;

DO $$ BEGIN
    CREATE SCHEMA IF NOT EXISTS supabase_functions;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ── 3. Ensure role grants are correct ──
-- These are idempotent and safe to re-run
DO $$ BEGIN
    GRANT supabase_auth_admin TO authenticator;
    GRANT supabase_storage_admin TO authenticator;
    GRANT supabase_functions_admin TO authenticator;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Additional role grants skipped: %', SQLERRM;
END $$;

-- ── 4. Webhooks infrastructure ──
DO $$ BEGIN
    CREATE TABLE IF NOT EXISTS supabase_functions.hooks (
        id BIGSERIAL PRIMARY KEY,
        hook_table_id INTEGER NOT NULL DEFAULT 0,
        hook_name TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        request_id BIGINT
    );
    CREATE INDEX IF NOT EXISTS idx_supabase_functions_hooks_request_id
        ON supabase_functions.hooks(request_id);
    CREATE INDEX IF NOT EXISTS idx_supabase_functions_hooks_h_table_id_h_name
        ON supabase_functions.hooks(hook_table_id, hook_name);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Webhooks table setup skipped: %', SQLERRM;
END $$;

-- ── 5. Webhook schema grants ──
DO $$ BEGIN
    GRANT USAGE ON SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;
    GRANT ALL ON ALL TABLES IN SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'supabase_functions grants skipped: %', SQLERRM;
END $$;
