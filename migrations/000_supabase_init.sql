-- =============================================================================
-- 000_supabase_init.sql — Additional Supabase setup
-- =============================================================================
-- Roles, schemas, extensions, and passwords are already created by
-- 99-run-migrations.sh BEFORE this file runs.
-- This file only adds extras not covered by the init script.
-- =============================================================================

-- Additional extensions (may not be available in all images)
DO $$ BEGIN
    CREATE EXTENSION IF NOT EXISTS pgjwt WITH SCHEMA extensions;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pgjwt extension not available: %', SQLERRM;
END $$;

DO $$ BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_stat_statements not available: %', SQLERRM;
END $$;

-- Webhooks infrastructure
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

DO $$ BEGIN
    GRANT ALL ON ALL TABLES IN SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;
EXCEPTION WHEN OTHERS THEN NULL; END $$;
