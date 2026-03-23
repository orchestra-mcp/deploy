-- =============================================================================
-- 000_supabase_init.sql — Supabase service prerequisites
-- =============================================================================
-- This runs BEFORE application migrations. It sets up the schemas, roles, and
-- functions required by Supabase services (GoTrue, Realtime, Storage, Edge Functions).
--
-- The supabase/postgres Docker image already creates the `auth` schema and core
-- extensions. This file handles everything else Supabase needs.
-- =============================================================================

-- ── 1. Extensions (in extensions schema for cleanliness) ──
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgjwt WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;  -- analytics
CREATE EXTENSION IF NOT EXISTS pg_net;  -- for webhooks (HTTP from DB)

-- ── 2. Supabase Internal Roles ──
-- The supabase/postgres Docker image creates these roles automatically
-- with LOGIN and passwords derived from POSTGRES_PASSWORD.
-- DO NOT create them here — if they exist before the image's init scripts
-- run, those scripts will skip them and they won't get passwords set.
--
-- Roles created by the image:
--   anon, authenticated, service_role, authenticator,
--   supabase_auth_admin, supabase_storage_admin, supabase_functions_admin,
--   supabase_admin, dashboard_user, pgbouncer, pgsodium_keyholder, etc.
--
-- We only ensure the role grants are correct (idempotent).

-- Role grants (safe to re-run — GRANT is idempotent in PG)
DO $$ BEGIN
    GRANT anon TO authenticator;
    GRANT authenticated TO authenticator;
    GRANT service_role TO authenticator;
    GRANT supabase_auth_admin TO authenticator;
    GRANT supabase_storage_admin TO authenticator;
    GRANT supabase_functions_admin TO authenticator;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Role grants skipped (roles not yet created by image): %', SQLERRM;
END $$;

DO $$ BEGIN
    GRANT anon TO postgres;
    GRANT authenticated TO postgres;
    GRANT service_role TO postgres;
    GRANT supabase_admin TO postgres;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Role grants to postgres skipped: %', SQLERRM;
END $$;

-- ── 3. Schemas ──
-- Use DO blocks to handle the case where schemas already exist with
-- a different owner (the Supabase image creates them).
DO $$ BEGIN CREATE SCHEMA IF NOT EXISTS auth; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER SCHEMA auth OWNER TO supabase_auth_admin; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN CREATE SCHEMA IF NOT EXISTS storage; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER SCHEMA storage OWNER TO supabase_storage_admin; EXCEPTION WHEN OTHERS THEN NULL; END $$;
CREATE SCHEMA IF NOT EXISTS _realtime;
CREATE SCHEMA IF NOT EXISTS _analytics;
DO $$ BEGIN CREATE SCHEMA IF NOT EXISTS supabase_functions; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER SCHEMA supabase_functions OWNER TO supabase_functions_admin; EXCEPTION WHEN OTHERS THEN NULL; END $$;
CREATE SCHEMA IF NOT EXISTS graphql_public;

-- Grant schema usage
DO $$ BEGIN
    GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
    GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Schema grants skipped: %', SQLERRM;
END $$;

-- ── 4. Default privileges ──
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

-- ── 5. JWT configuration ──
-- These are used by PostgREST to verify JWT tokens
ALTER DATABASE postgres SET "app.settings.jwt_secret" TO 'super-secret-jwt-token-with-at-least-32-characters-long';
ALTER DATABASE postgres SET "app.settings.jwt_exp" TO '3600';

-- ── 6. auth.uid() and auth.role() helper functions ──
-- These are the standard Supabase helper functions used in RLS policies

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS UUID AS $$
    SELECT NULLIF(
        current_setting('request.jwt.claims', true)::jsonb->>'sub',
        ''
    )::UUID;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS TEXT AS $$
    SELECT NULLIF(
        current_setting('request.jwt.claims', true)::jsonb->>'role',
        ''
    )::TEXT;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION auth.email()
RETURNS TEXT AS $$
    SELECT NULLIF(
        current_setting('request.jwt.claims', true)::jsonb->>'email',
        ''
    )::TEXT;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION auth.jwt()
RETURNS JSONB AS $$
    SELECT COALESCE(
        current_setting('request.jwt.claims', true),
        '{}'
    )::JSONB;
$$ LANGUAGE sql STABLE;

-- ── 7. Webhooks infrastructure (supabase_functions schema) ──
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

-- Grant webhook function access
DO $$ BEGIN
    GRANT USAGE ON SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;
    GRANT ALL ON ALL TABLES IN SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'supabase_functions grants skipped: %', SQLERRM;
END $$;

-- ── 8. Realtime schema ownership ──
DO $$ BEGIN
    ALTER SCHEMA _realtime OWNER TO postgres;
    GRANT USAGE ON SCHEMA _realtime TO postgres;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ── 9. Analytics schema ownership ──
DO $$ BEGIN
    ALTER SCHEMA _analytics OWNER TO postgres;
    GRANT USAGE ON SCHEMA _analytics TO postgres;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ── 10. Storage schema permissions ──
DO $$ BEGIN
    GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;
    GRANT ALL ON ALL TABLES IN SCHEMA storage TO anon, authenticated, service_role;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO anon, authenticated, service_role;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'storage grants skipped: %', SQLERRM;
END $$;

-- ── 11. Auth schema permissions ──
DO $$ BEGIN
    GRANT USAGE ON SCHEMA auth TO supabase_auth_admin, service_role;
    GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;
    GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'auth grants skipped: %', SQLERRM;
END $$;
