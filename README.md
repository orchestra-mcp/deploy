# Orchestra MCP — Self-Hosted Deployment

Single command to deploy the entire Orchestra MCP platform.

## One-Command Install

```bash
curl -fsSL https://raw.githubusercontent.com/orchestra-mcp/deploy/master/setup-server.sh | sudo bash
```

This will:
1. Install Docker + Compose v2
2. Clone this repo to `/opt/orchestra`
3. Prompt you for each password/token (or auto-generate securely)
4. Generate Supabase API keys (ANON_KEY + SERVICE_ROLE_KEY)
5. Write `.env` with all secrets
6. Deploy all 16 containers

## Manual Setup

```bash
git clone https://github.com/orchestra-mcp/deploy.git /opt/orchestra
cd /opt/orchestra
cp .env.example .env
# Edit .env — fill in all required secrets (see comments in file)
docker compose up -d
```

## Architecture

```
                        Caddy (TLS + routing)
                               │
      ┌────────────┬───────────┼──────────────────────────┐
      │            │           │                          │
orchestra-   api. + mcp.    *.orchestra-mcp.dev
 mcp.dev       │              Supabase services:
(Next.js)      │               ├── db.       (Studio + basicauth)
               │               ├── auth.     (GoTrue)
         ┌─────┴──────────┐   ├── rest.     (PostgREST via Kong)
         │  Go Gateway     │   ├── realtime. (Realtime)
         │  (unified)      │   ├── storage.  (Storage)
         │  -REST API      │   └── edge.     (Edge Functions)
         │  -Tunnels       │
         │  -MCP (SSE)     │
         │  -100+ tools    │
         └─────────────────┘
```

## Services (16 containers)

| Service | Image | Subdomain | Auth |
|---------|-------|-----------|------|
| PostgreSQL | supabase/postgres:15.8.1.085 | — (internal) | — |
| GoTrue (Auth) | supabase/gotrue:v2.186.0 | auth. | Public |
| PostgREST | postgrest/postgrest:v14.6 | rest. (via Kong) | API key |
| Realtime | supabase/realtime:v2.76.5 | realtime. | JWT |
| Storage | supabase/storage-api:v1.44.2 | storage. | JWT |
| Studio | supabase/studio:2026.03.16 | db. | **Basic auth** (DASHBOARD_USERNAME/PASSWORD) |
| Edge Runtime | supabase/edge-runtime:v1.71.2 | edge. | JWT |
| Kong | kong/kong:3.9.1 | — (internal) | — |
| Postgres Meta | supabase/postgres-meta:v0.95.2 | — (internal) | — |
| imgproxy | darthsim/imgproxy:v3.30.1 | — (internal) | — |
| Supavisor | supabase/supavisor:2.7.4 | — (internal) | — |
| ClickHouse | clickhouse/clickhouse-server:25.3 | analytics. | **Basic auth** (CLICKHOUSE_ADMIN_USER) |
| Supabase MCP | supabase/mcp:latest | — (internal) | — |
| Gateway | orchestra-mcp/gateway | api. + mcp. (unified) | JWT |
| Next.js | orchestra-mcp/web | orchestra-mcp.dev | Public |
| Caddy | custom (xcaddy+cloudflare) | — (edge) | — |

## Interactive Setup Prompts

The setup script prompts for each value with the option to auto-generate:

| Prompt | Auto-generate | Notes |
|--------|:---:|-------|
| Domain | Default: `orchestra-mcp.dev` | Used in Caddyfile + docker-compose |
| Cloudflare API Token | — | Required for wildcard TLS |
| PostgreSQL Password | Yes (24-byte hex) | Enter own or press Enter |
| JWT Secret | Yes (32-byte hex) | Enter own or press Enter |
| Realtime Secret Key Base | Yes (64-byte hex) | Enter own or press Enter |
| Supavisor Secret Key Base | Yes (32-byte hex) | Enter own or press Enter |
| Vault Encryption Key | Yes (16-byte hex) | Enter own or press Enter |
| Realtime DB Encryption Key | Yes (16-byte hex) | Enter own or press Enter |
| ClickHouse Password | Yes (16-byte hex) | Enter own or press Enter |
| Studio Username | Default: `supabase` | For db.domain.com login |
| Studio Password | Yes (12-byte hex) | Must include a letter |
| GitHub OAuth | — | Optional: Client ID + Secret |
| Google OAuth | — | Optional: Client ID + Secret |
| SMTP | — | Optional: host, port, user, pass |

## Directory Structure

```
deploy/
├── docker-compose.yml       # All 16 services
├── Caddyfile                # Subdomain routing + TLS + basicauth
├── kong.yml                 # Kong API gateway config
├── .env.example             # Environment variable template
├── setup-server.sh          # One-command interactive setup
├── deploy.sh                # Day-to-day management
├── docker/
│   └── caddy/
│       └── Dockerfile       # xcaddy with cloudflare DNS plugin
├── clickhouse/
│   ├── config.xml
│   ├── users.xml
│   └── init/
│       ├── 001_analytics_schema.sql
│       └── 002_audit_schema.sql
├── supabase/
│   └── functions/
│       └── main/
│           └── index.ts     # Edge function entry point
├── migrations/              # PostgreSQL migrations (24 files)
│   ├── 000_supabase_init.sql ... 023_rls_audit_realtime_addendum.sql
├── docs/
│   └── README.md            # Detailed deployment guide
└── .github/
    ├── FUNDING.yml
    ├── ISSUE_TEMPLATE/
    └── workflows/
        ├── build-gateway.yml # Build + push gateway image on apps/gateway/** changes
        ├── deploy.yml        # Manual SSH deploy (workflow_dispatch)
        └── validate.yml      # CI: validate compose + caddy + migrations
```

## Security

- **Studio** (`db.orchestra-mcp.dev`) — protected by Caddy basic auth + Studio internal auth
- **ClickHouse** (`analytics.orchestra-mcp.dev`) — protected by Caddy basic auth
- **PostgREST** (`rest.orchestra-mcp.dev`) — requires `apikey` header (ANON_KEY or SERVICE_ROLE_KEY)
- **All services** — TLS via Cloudflare DNS-01 wildcard certificate
- **`.env`** — file permissions set to 600 (owner read/write only)

## Updating

```bash
cd /opt/orchestra
docker compose pull    # Pull latest images
docker compose up -d   # Recreate changed containers
```

Or use the deploy script:
```bash
./deploy.sh            # Pull + restart
./deploy.sh --status   # Check health
./deploy.sh --logs     # View logs
```

## CI/CD

Deploy is triggered manually from GitHub Actions:
1. Go to **Actions > Deploy to Production**
2. Click **Run workflow**
3. Optionally specify a single service to restart

Required GitHub secrets: `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_KNOWN_HOSTS`

## Payment Gateways

- **GitHub Sponsors** — `https://api.orchestra-mcp.dev/webhooks/github-sponsors`
- **Buy Me a Coffee** — `https://api.orchestra-mcp.dev/webhooks/buymeacoffee`

## Migrations

24 PostgreSQL migration files in `migrations/`, run automatically on first boot. Includes: extensions, users, teams, projects, features, notes, agents, health, sessions, settings, API collections, presentations, community, admin, tunnels, feature flags, RLS, realtime, audit trail, CMS/i18n, subscriptions, notifications.
