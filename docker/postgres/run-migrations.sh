#!/bin/bash
# =============================================================================
# Run Orchestra migrations from /docker-entrypoint-initdb.d/migrations/
#
# PostgreSQL's entrypoint only processes files directly in initdb.d/,
# not subdirectories. This script runs all .sql files from migrations/
# in alphabetical order after the Supabase image's own init scripts.
#
# Named 99-run-migrations.sh so it runs LAST (after Supabase's migrate.sh
# creates its internal roles, schemas, and extensions).
#
# IMPORTANT: This also sets passwords on Supabase internal roles. The
# supabase/postgres image creates roles via migrate.sh but does NOT set
# passwords. The official docker-compose uses roles.sql for this, but that
# file runs too early (before migrate.sh creates the roles). So we set
# passwords here, after everything is created.
# =============================================================================

set -e

MIGRATIONS_DIR="/docker-entrypoint-initdb.d/migrations"

# ── Step 1: Set passwords on Supabase internal roles ──
# These roles were created by the image's migrate.sh (which ran before us).
# Without passwords, GoTrue/Storage/PostgREST can't authenticate.
echo "Setting passwords on Supabase internal roles..."

psql -v ON_ERROR_STOP=0 --username "${POSTGRES_USER:-supabase_admin}" --dbname "${POSTGRES_DB:-postgres}" <<-EOSQL
    DO \$\$
    DECLARE
        pgpass TEXT := '${POSTGRES_PASSWORD}';
    BEGIN
        -- Core service roles
        EXECUTE format('ALTER USER authenticator WITH PASSWORD %L', pgpass);
        EXECUTE format('ALTER USER supabase_auth_admin WITH PASSWORD %L', pgpass);
        EXECUTE format('ALTER USER supabase_storage_admin WITH PASSWORD %L', pgpass);
        EXECUTE format('ALTER USER supabase_functions_admin WITH PASSWORD %L', pgpass);
        EXECUTE format('ALTER USER pgbouncer WITH PASSWORD %L', pgpass);

        -- Also ensure authenticator can login and has role grants
        ALTER USER authenticator WITH LOGIN;

        RAISE NOTICE 'Supabase role passwords set successfully';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Some role passwords could not be set: %', SQLERRM;
    END \$\$;
EOSQL

echo "Role passwords configured."

# ── Step 2: Run Orchestra application migrations ──
if [ ! -d "$MIGRATIONS_DIR" ]; then
    echo "No migrations directory found, skipping."
    exit 0
fi

echo "Running Orchestra migrations..."

for f in "$MIGRATIONS_DIR"/*.sql; do
    [ -f "$f" ] || continue
    echo "  → $(basename "$f")"
    psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER:-supabase_admin}" --dbname "${POSTGRES_DB:-postgres}" -f "$f"
done

echo "Orchestra migrations complete."
