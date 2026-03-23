-- 001_create_extensions.sql
-- Enable required PostgreSQL extensions and create PostgREST roles.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Extensions
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- PostgREST Roles
-- =============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
        COMMENT ON ROLE anon IS 'Anonymous (unauthenticated) PostgREST role';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
        COMMENT ON ROLE authenticated IS 'Authenticated PostgREST role';
    END IF;
END
$$;

-- Grant usage on the public schema to both roles
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
