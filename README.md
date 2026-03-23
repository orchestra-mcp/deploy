# Orchestra MCP — Self-Hosted Deployment

Single `docker compose up -d` to deploy the entire Orchestra MCP platform.

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/orchestra-mcp/deploy.git
cd deploy

# 2. Configure environment
cp .env.example .env
# Edit .env — fill in all required secrets (see comments in file)

# 3. Deploy
docker compose up -d

# 4. Check status
docker compose ps
docker compose logs -f
```

## Architecture

```
                        Caddy (TLS + routing)
                               │
      ┌────────────┬───────────┼───────────┬──────────────┐
      │            │           │           │              │
orchestra-     api.        mcp.      *.orchestra-mcp.dev
 mcp.dev       │            │         Supabase services:
(Next.js)      │            │          ├── db.       (Studio)
               │            │          ├── auth.     (GoTrue)
         ┌─────┴──────┐ ┌───┴────┐   ├── rest.     (PostgREST)
         │ Go Gateway  │ │Cloud   │   ├── realtime. (Realtime)
         │ -Tunnels    │ │MCP     │   ├── storage.  (Storage)
         │ -Actions    │ │-SSE    │   └── edge.     (Edge Functions)
         │ -Health     │ │-100+   │
         └─────────────┘ │tools   │
                └────────┴────────┘
                same Go binary
```

## Services (16 containers)

| Service | Image | Subdomain | Port |
|---------|-------|-----------|------|
| PostgreSQL | supabase/postgres:15.8.1.085 | — (internal) | 5432 |
| GoTrue (Auth) | supabase/gotrue:v2.186.0 | auth. | 9999 |
| PostgREST | postgrest/postgrest:v14.6 | rest. (via Kong) | 3000 |
| Realtime | supabase/realtime:v2.76.5 | realtime. | 4000 |
| Storage | supabase/storage-api:v1.44.2 | storage. | 5000 |
| Studio | supabase/studio:2026.03.16 | db. | 3000 |
| Edge Runtime | supabase/edge-runtime:v1.71.2 | edge. | 8081 |
| Kong | kong/kong:3.9.1 | — (internal) | 8000 |
| Postgres Meta | supabase/postgres-meta:v0.95.2 | — (internal) | 8080 |
| imgproxy | darthsim/imgproxy:v3.30.1 | — (internal) | 5001 |
| Supavisor | supabase/supavisor:2.7.4 | — (internal) | 4000 |
| ClickHouse | clickhouse/clickhouse-server:25.3 | analytics. | 8123 |
| Supabase MCP | supabase/mcp:latest | — (internal) | — |
| Gateway | orchestra-mcp/gateway | api. + mcp. | 8080 |
| Next.js | orchestra-mcp/web | orchestra-mcp.dev | 3000 |
| Caddy | custom (xcaddy+cloudflare) | — (edge) | 80,443 |

## Directory Structure

```
apps/deploy/
├── docker-compose.yml       # All 16 services
├── Caddyfile                # Subdomain routing + TLS
├── kong.yml                 # Kong API gateway config
├── .env.example             # Environment variable template
├── docker/
│   └── caddy/
│       └── Dockerfile       # xcaddy with cloudflare DNS plugin
├── clickhouse/
│   ├── config.xml           # ClickHouse server config
│   ├── users.xml            # ClickHouse user profiles
│   └── init/
│       ├── 001_analytics_schema.sql
│       └── 002_audit_schema.sql
├── supabase/
│   └── functions/
│       └── main/
│           └── index.ts     # Edge function entry point
├── migrations/              # PostgreSQL migrations (24 files)
│   ├── 000_supabase_init.sql
│   ├── 000b_supabase_logging.sql
│   ├── 001_create_extensions.sql
│   ├── ...
│   ├── 022_enhance_notifications.sql
│   └── 023_rls_audit_realtime_addendum.sql
└── README.md
```

## Generating Secrets

```bash
# JWT Secret (used by all Supabase services)
openssl rand -hex 32

# Realtime Secret Key Base (64+ chars)
openssl rand -hex 64

# Supabase API Keys (ANON_KEY and SERVICE_ROLE_KEY)
# Generate JWTs at: https://supabase.com/docs/guides/self-hosting#api-keys

# Cloudflare API Token
# Create at: https://dash.cloudflare.com/profile/api-tokens
# Needs Zone:DNS:Edit for your domain
```

## Updating

```bash
docker compose pull    # Pull latest images
docker compose up -d   # Recreate changed containers
```

## Payment Gateways

Only two payment gateways are supported:
- **GitHub Sponsors** — webhook events at `/api/webhooks/github-sponsors`
- **Buy Me a Coffee** — webhook events at `/api/webhooks/buymeacoffee`

## Migrations

All PostgreSQL migrations are in `migrations/` and run automatically on first boot via Docker's `docker-entrypoint-initdb.d`. They are:
- Numbered sequentially (000, 001, ..., 023)
- Idempotent (safe to re-run)
- Include: extensions, users, teams, projects, features, notes, agents, health, sessions, settings, API collections, presentations, community, admin, tunnels, feature flags, RLS, realtime, audit trail, CMS/i18n, subscriptions, notifications
