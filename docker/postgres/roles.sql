-- =============================================================================
-- roles.sql — Set passwords on Supabase internal roles
-- =============================================================================
-- The supabase/postgres Docker image creates these roles during its own init,
-- but does NOT set passwords on them. This script runs as part of
-- docker-entrypoint-initdb.d to set POSTGRES_PASSWORD on each role.
--
-- This mirrors the official Supabase self-hosted docker-compose setup:
-- https://github.com/supabase/supabase/blob/master/docker/volumes/db/roles.sql
-- =============================================================================

-- NOTE: change to your own passwords for production environments
\set pgpass `echo "$POSTGRES_PASSWORD"`

ALTER USER authenticator WITH PASSWORD :'pgpass';
ALTER USER pgbouncer WITH PASSWORD :'pgpass';
ALTER USER supabase_auth_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_functions_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_storage_admin WITH PASSWORD :'pgpass';
