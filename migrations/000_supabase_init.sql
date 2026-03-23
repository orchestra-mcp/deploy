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
-- These roles are used by PostgREST, GoTrue, Storage, etc.

DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN NOINHERIT;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN NOINHERIT;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
        CREATE ROLE authenticator NOINHERIT LOGIN;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
        CREATE ROLE supabase_auth_admin NOLOGIN NOINHERIT CREATEROLE;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
        CREATE ROLE supabase_storage_admin NOLOGIN NOINHERIT;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_functions_admin') THEN
        CREATE ROLE supabase_functions_admin NOLOGIN NOINHERIT;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_admin') THEN
        CREATE ROLE supabase_admin NOLOGIN NOINHERIT BYPASSRLS CREATEROLE CREATEDB;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dashboard_user') THEN
        CREATE ROLE dashboard_user NOLOGIN NOINHERIT CREATEROLE CREATEDB REPLICATION;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pgbouncer') THEN
        CREATE ROLE pgbouncer NOLOGIN NOINHERIT;
    END IF;
END $$;

-- Role grants
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;
GRANT supabase_auth_admin TO authenticator;
GRANT supabase_storage_admin TO authenticator;
GRANT supabase_functions_admin TO authenticator;

-- Grant roles to postgres (superuser)
GRANT anon TO postgres;
GRANT authenticated TO postgres;
GRANT service_role TO postgres;
GRANT supabase_admin TO postgres;

-- ── 3. Schemas ──
CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;
CREATE SCHEMA IF NOT EXISTS storage AUTHORIZATION supabase_storage_admin;
CREATE SCHEMA IF NOT EXISTS _realtime;
CREATE SCHEMA IF NOT EXISTS _analytics;
CREATE SCHEMA IF NOT EXISTS supabase_functions AUTHORIZATION supabase_functions_admin;
CREATE SCHEMA IF NOT EXISTS graphql_public;

-- Grant schema usage
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;

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
GRANT USAGE ON SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;

-- ── 8. Realtime schema ownership ──
ALTER SCHEMA _realtime OWNER TO postgres;
GRANT USAGE ON SCHEMA _realtime TO postgres;

-- ── 9. Analytics schema ownership ──
ALTER SCHEMA _analytics OWNER TO postgres;
GRANT USAGE ON SCHEMA _analytics TO postgres;

-- ── 10. Storage schema permissions ──
GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA storage TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO anon, authenticated, service_role;

-- ── 11. Auth schema permissions ──
GRANT USAGE ON SCHEMA auth TO supabase_auth_admin, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin;
