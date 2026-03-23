#!/bin/bash
# =============================================================================
# Run Orchestra migrations from /docker-entrypoint-initdb.d/migrations/
#
# Named 99-run-migrations.sh so it runs LAST in docker-entrypoint-initdb.d/.
#
# Creates ALL Supabase internal roles, sets passwords, creates schemas,
# then runs application migrations in order.
# =============================================================================

set -e

PG_USER="${POSTGRES_USER:-supabase_admin}"
PG_DB="${POSTGRES_DB:-postgres}"
PG_PASS="${POSTGRES_PASSWORD}"
MIGRATIONS_DIR="/docker-entrypoint-initdb.d/migrations"

run_sql() {
    psql -v ON_ERROR_STOP=1 --username "$PG_USER" --dbname "$PG_DB" "$@"
}

# ── Step 1: Create Supabase internal roles ──
echo "=== Step 1: Creating Supabase internal roles ==="

# First ensure supabase_admin is superuser (it should be from initdb)
run_sql <<'EOSQL'
-- Verify we have superuser
DO $$ BEGIN
    IF NOT (SELECT usesuper FROM pg_user WHERE usename = current_user) THEN
        RAISE EXCEPTION 'Current user % is not superuser', current_user;
    END IF;
    RAISE NOTICE 'Running as superuser: %', current_user;
END $$;

-- Create all roles with idempotent DO blocks
DO $$ BEGIN CREATE ROLE anon NOLOGIN NOINHERIT; RAISE NOTICE 'Created role: anon'; EXCEPTION WHEN duplicate_object THEN RAISE NOTICE 'Role anon already exists'; END $$;
DO $$ BEGIN CREATE ROLE authenticated NOLOGIN NOINHERIT; RAISE NOTICE 'Created role: authenticated'; EXCEPTION WHEN duplicate_object THEN RAISE NOTICE 'Role authenticated already exists'; END $$;
DO $$ BEGIN CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS; RAISE NOTICE 'Created role: service_role'; EXCEPTION WHEN duplicate_object THEN RAISE NOTICE 'Role service_role already exists'; END $$;
DO $$ BEGIN CREATE ROLE authenticator NOINHERIT LOGIN; RAISE NOTICE 'Created role: authenticator'; EXCEPTION WHEN duplicate_object THEN RAISE NOTICE 'Role authenticator already exists'; END $$;
DO $$ BEGIN CREATE ROLE supabase_auth_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION; RAISE NOTICE 'Created role: supabase_auth_admin'; EXCEPTION WHEN duplicate_object THEN RAISE NOTICE 'Role supabase_auth_admin already exists'; END $$;
DO $$ BEGIN CREATE ROLE supabase_storage_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION; RAISE NOTICE 'Created role: supabase_storage_admin'; EXCEPTION WHEN duplicate_object THEN RAISE NOTICE 'Role supabase_storage_admin already exists'; END $$;
DO $$ BEGIN CREATE ROLE supabase_functions_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION; RAISE NOTICE 'Created role: supabase_functions_admin'; EXCEPTION WHEN duplicate_object THEN RAISE NOTICE 'Role supabase_functions_admin already exists'; END $$;
DO $$ BEGIN CREATE ROLE dashboard_user NOSUPERUSER CREATEDB CREATEROLE REPLICATION; RAISE NOTICE 'Created role: dashboard_user'; EXCEPTION WHEN duplicate_object THEN RAISE NOTICE 'Role dashboard_user already exists'; END $$;
DO $$ BEGIN CREATE ROLE pgbouncer LOGIN; RAISE NOTICE 'Created role: pgbouncer'; EXCEPTION WHEN duplicate_object THEN RAISE NOTICE 'Role pgbouncer already exists'; END $$;
DO $$ BEGIN CREATE ROLE supabase_replication_admin LOGIN REPLICATION; RAISE NOTICE 'Created role: supabase_replication_admin'; EXCEPTION WHEN duplicate_object THEN RAISE NOTICE 'Role supabase_replication_admin already exists'; END $$;
DO $$ BEGIN CREATE ROLE supabase_read_only_user LOGIN BYPASSRLS; RAISE NOTICE 'Created role: supabase_read_only_user'; EXCEPTION WHEN duplicate_object THEN RAISE NOTICE 'Role supabase_read_only_user already exists'; END $$;
DO $$ BEGIN CREATE ROLE postgres SUPERUSER LOGIN REPLICATION BYPASSRLS; RAISE NOTICE 'Created role: postgres'; EXCEPTION WHEN duplicate_object THEN RAISE NOTICE 'Role postgres already exists'; END $$;

-- Role grants
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;
GRANT supabase_admin TO authenticator;
ALTER ROLE authenticator LOGIN;

EOSQL

echo "=== Roles created ==="

# ── Step 2: Set passwords ──
echo "=== Step 2: Setting role passwords ==="

run_sql -v pgpass="$PG_PASS" <<'EOSQL'
ALTER USER authenticator WITH PASSWORD :'pgpass';
ALTER USER supabase_auth_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_storage_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_functions_admin WITH PASSWORD :'pgpass';
ALTER USER pgbouncer WITH PASSWORD :'pgpass';
ALTER USER postgres WITH PASSWORD :'pgpass';
EOSQL

echo "=== Passwords set ==="

# ── Step 3: Create schemas and extensions ──
echo "=== Step 3: Creating schemas and extensions ==="

run_sql <<'EOSQL'
-- Extensions
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- Auth schema (owned by supabase_auth_admin so GoTrue can manage it)
CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;
GRANT ALL PRIVILEGES ON SCHEMA auth TO supabase_auth_admin;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;

-- Storage schema
CREATE SCHEMA IF NOT EXISTS storage AUTHORIZATION supabase_admin;
GRANT ALL ON SCHEMA storage TO supabase_storage_admin WITH GRANT OPTION;
GRANT USAGE ON SCHEMA storage TO postgres, anon, authenticated, service_role;

-- Other schemas
CREATE SCHEMA IF NOT EXISTS _realtime;
CREATE SCHEMA IF NOT EXISTS _analytics;
CREATE SCHEMA IF NOT EXISTS supabase_functions;
CREATE SCHEMA IF NOT EXISTS graphql_public;

-- Public schema grants
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA extensions TO postgres, anon, authenticated, service_role;

-- Default privileges
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;

-- Auth admin setup
ALTER USER supabase_auth_admin SET search_path = 'auth';
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;

-- Storage admin setup
ALTER USER supabase_storage_admin SET search_path = 'storage';
GRANT CREATE ON DATABASE postgres TO supabase_storage_admin;

-- Dashboard user grants
GRANT ALL ON DATABASE postgres TO dashboard_user;
GRANT ALL ON SCHEMA auth TO dashboard_user;
GRANT ALL ON SCHEMA extensions TO dashboard_user;
GRANT ALL ON SCHEMA storage TO dashboard_user;

-- supabase_functions grants
GRANT USAGE ON SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;

-- Realtime publication
DO $$ BEGIN CREATE PUBLICATION supabase_realtime; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Auth helper functions — created AS supabase_auth_admin so GoTrue can replace them
SET ROLE supabase_auth_admin;

CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION auth.role() RETURNS text AS $$
  SELECT nullif(current_setting('request.jwt.claim.role', true), '')::text;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION auth.email() RETURNS text AS $$
  SELECT nullif(current_setting('request.jwt.claim.email', true), '')::text;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb AS $$
  SELECT coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb;
$$ LANGUAGE sql STABLE;

RESET ROLE;
EOSQL

echo "=== Schemas and extensions ready ==="

# ── Step 4: Run application migrations ──
if [ ! -d "$MIGRATIONS_DIR" ]; then
    echo "No migrations directory found, skipping."
    exit 0
fi

echo "=== Step 4: Running Orchestra migrations ==="

for f in "$MIGRATIONS_DIR"/*.sql; do
    [ -f "$f" ] || continue
    echo "  → $(basename "$f")"
    run_sql -f "$f"
done

echo "=== Orchestra migrations complete ==="
