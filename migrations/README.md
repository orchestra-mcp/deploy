# SQL Migrations

Centralized PostgreSQL migration files for the Orchestra platform. These replace scattered GORM AutoMigrate, PowerSync migrations, and Laravel migrations with a single source of truth.

## Convention

- Files are numbered sequentially: `NNN_description.sql`
- Each file is **idempotent** -- safe to run multiple times (`CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`)
- Files must be applied **in order** (foreign keys depend on earlier tables)
- All tables use `TIMESTAMPTZ` for timestamps (never bare `TIMESTAMP`)
- Soft deletes use a nullable `deleted_at TIMESTAMPTZ` column
- Default primary key is `UUID DEFAULT gen_random_uuid()` unless noted otherwise
- `users` uses `BIGSERIAL` (for GORM uint compatibility)
- `JSONB` is used for flexible/nested data; `TEXT[]` for simple arrays
- CHECK constraints enforce valid enum values at the database level

## File Inventory

| File | Tables | Description |
|------|--------|-------------|
| `001_create_extensions.sql` | -- | Extensions (uuid-ossp, pgcrypto) and PostgREST roles (anon, authenticated) |
| `002_create_users.sql` | 7 | users, passkeys, oauth_accounts, device_tokens, otp_codes, magic_link_tokens, user_verifications, verification_types |
| `003_create_teams.sql` | 2 | teams, memberships |
| `004_create_projects.sql` | 3 | workspaces, workspace_teams, projects |
| `005_create_features.sql` | 6 | features, plans, requests, epics, stories, tasks |
| `006_create_notes.sql` | 3 | notes, note_revisions, docs |
| `007_create_agents.sql` | 5 | agents, skills, workflows, project_skills, project_agents |
| `008_create_health.sql` | 8 | health_profiles, water_logs, meal_logs, caffeine_logs, pomodoro_sessions, sleep_configs, sleep_logs, health_snapshots |
| `009_create_sessions.sql` | 5 | ai_sessions, session_turns, persons, delegations, assignment_rules |
| `010_create_settings.sql` | 5 | user_settings, system_settings, subscriptions, user_integrations, push_subscriptions |
| `011_create_api_collections.sql` | 3 | api_collections, api_endpoints, api_environments |
| `012_create_presentations.sql` | 2 | presentations, presentation_slides |
| `013_create_community.sql` | 8 | community_posts, community_likes, comments, issues, sponsors, contact_messages, pages, posts |
| `014_create_admin.sql` | 6 | badge_definitions, user_badges, user_wallets, points_transactions, github_repos, github_issues |
| `015_create_tunnels.sql` | 14 | tunnels, shared_contents, share_comments, team_shares, content_views, custom_domains, action_histories, action_logs, mcp_event_logs, sync_logs, conflict_logs, repo_workspaces, notifications, packs |

**Total: 77 tables across 15 migration files.**

## Running Migrations

Apply all migrations in order against a PostgreSQL database:

```bash
# Using psql
for f in migrations/*.sql; do
  psql "$DATABASE_URL" -f "$f"
done

# Or individually
psql "$DATABASE_URL" -f migrations/001_create_extensions.sql
psql "$DATABASE_URL" -f migrations/002_create_users.sql
# ... etc
```

## Foreign Key Strategy

- **ON DELETE CASCADE**: Child tables that have no meaning without the parent (e.g., session_turns -> ai_sessions, passkeys -> users)
- **ON DELETE SET NULL**: Optional references where the child should survive parent deletion (e.g., projects.team_id -> teams)
- All `user_id` columns on user-owned entities use `ON DELETE CASCADE`

## Adding New Migrations

1. Create the next numbered file: `016_description.sql`
2. Use `CREATE TABLE IF NOT EXISTS` and `CREATE INDEX IF NOT EXISTS`
3. Add `COMMENT ON TABLE` for documentation
4. Add appropriate CHECK constraints for enum-like columns
5. Reference this README's file inventory and update the table count
