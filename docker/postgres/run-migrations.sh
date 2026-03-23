#!/bin/bash
# =============================================================================
# Run Orchestra migrations from /docker-entrypoint-initdb.d/migrations/
#
# Named 99-run-migrations.sh so it runs LAST in docker-entrypoint-initdb.d/.
#
# This script:
#   1. Creates ALL Supabase internal roles (the image does NOT create them)
#   2. Sets passwords on all roles using POSTGRES_PASSWORD
#   3. Creates required schemas
#   4. Runs application migrations in alphabetical order
# =============================================================================

set -e

PG_USER="${POSTGRES_USER:-supabase_admin}"
PG_DB="${POSTGRES_DB:-postgres}"
PG_PASS="${POSTGRES_PASSWORD}"
MIGRATIONS_DIR="/docker-entrypoint-initdb.d/migrations"

run_sql() {
    psql -v ON_ERROR_STOP=0 --username "$PG_USER" --dbname "$PG_DB" "$@"
}

run_sql_strict() {
    psql -v ON_ERROR_STOP=1 --username "$PG_USER" --dbname "$PG_DB" "$@"
}

# ── Step 1: Create Supabase internal roles ──
echo "Creating Supabase internal roles..."

run_sql <<'EOSQL'
-- PostgREST / GoTrue / client SDK roles
DO $$ BEGIN CREATE ROLE anon NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticated NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticator NOINHERIT LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Service admin roles
DO $$ BEGIN CREATE ROLE supabase_auth_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE supabase_storage_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE supabase_functions_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE dashboard_user NOSUPERUSER CREATEDB CREATEROLE REPLICATION; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE pgbouncer LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE supabase_replication_admin LOGIN REPLICATION; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE supabase_read_only_user LOGIN BYPASSRLS; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- postgres role (if not created by image)
DO $$ BEGIN CREATE ROLE postgres SUPERUSER LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Role grants
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;
GRANT supabase_admin TO authenticator;

-- Ensure LOGIN on authenticator
ALTER ROLE authenticator LOGIN;

EOSQL

echo "Roles created."

# ── Step 2: Set passwords using POSTGRES_PASSWORD ──
echo "Setting role passwords..."

# Use psql \set to safely handle passwords with special characters
run_sql -v pgpass="$PG_PASS" <<'EOSQL'
ALTER USER authenticator WITH PASSWORD :'pgpass';
ALTER USER supabase_auth_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_storage_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_functions_admin WITH PASSWORD :'pgpass';
ALTER USER pgbouncer WITH PASSWORD :'pgpass';
ALTER USER postgres WITH PASSWORD :'pgpass';
EOSQL

echo "Passwords set."

# ── Step 3: Create schemas and extensions ──
echo "Creating schemas and extensions..."

run_sql <<'EOSQL'
-- Extensions
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- Auth schema
CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_admin;
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

-- Auth helper functions
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
EOSQL

echo "Schemas and extensions ready."

# ── Step 4: Run application migrations ──
if [ ! -d "$MIGRATIONS_DIR" ]; then
    echo "No migrations directory found, skipping."
    exit 0
fi

echo "Running Orchestra migrations..."

for f in "$MIGRATIONS_DIR"/*.sql; do
    [ -f "$f" ] || continue
    echo "  → $(basename "$f")"
    run_sql_strict -f "$f"
done

echo "Orchestra migrations complete."
