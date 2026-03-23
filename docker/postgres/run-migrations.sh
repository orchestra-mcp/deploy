#!/bin/bash
# =============================================================================
# Run Orchestra migrations from /docker-entrypoint-initdb.d/migrations/
#
# PostgreSQL's entrypoint only processes files directly in initdb.d/,
# not subdirectories. This script runs all .sql files from migrations/
# in alphabetical order after the Supabase image's own init scripts.
#
# Named 99-run-migrations.sh so it runs LAST (after Supabase creates
# its internal roles, schemas, and extensions).
# =============================================================================

set -e

MIGRATIONS_DIR="/docker-entrypoint-initdb.d/migrations"

if [ ! -d "$MIGRATIONS_DIR" ]; then
    echo "No migrations directory found, skipping."
    exit 0
fi

echo "Running Orchestra migrations..."

for f in "$MIGRATIONS_DIR"/*.sql; do
    [ -f "$f" ] || continue
    echo "  → $(basename "$f")"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$f"
done

echo "Orchestra migrations complete."
