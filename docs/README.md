# Orchestra MCP — Server Deployment Guide

Step-by-step instructions to deploy the full Orchestra MCP platform on a fresh server.

---

## Prerequisites

- A Linux server (Ubuntu 22.04+ recommended) with Docker and Docker Compose v2 installed
- A domain pointed to your server (we use `orchestra-mcp.dev`)
- A Cloudflare account with the domain zone configured (for DNS-01 TLS)
- At least 4GB RAM, 2 vCPUs, 40GB disk

---

## Step 1: Push `apps/deploy/` to its Own Repo

From your local machine:

```bash
cd ~/Sites/orchestra-agents/apps/deploy
git init
git add -A
git commit -m "Initial deploy setup — Supabase self-hosted stack"
git remote add origin git@github.com:orchestra-mcp/deploy.git
git push -u origin main
```

---

## Step 2: SSH into Your Server and Clone

```bash
ssh your-server
git clone git@github.com:orchestra-mcp/deploy.git /opt/orchestra
cd /opt/orchestra
```

---

## Step 3: Generate Secrets

```bash
# JWT Secret (shared by all Supabase services)
JWT_SECRET=$(openssl rand -hex 32)
echo "JWT_SECRET=$JWT_SECRET"

# Postgres password
POSTGRES_PASSWORD=$(openssl rand -hex 24)
echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD"

# Realtime secret (needs 64+ chars)
REALTIME_SECRET=$(openssl rand -hex 64)
echo "REALTIME_SECRET_KEY_BASE=$REALTIME_SECRET"

# Supavisor secrets
SECRET_KEY_BASE=$(openssl rand -hex 32)
echo "SECRET_KEY_BASE=$SECRET_KEY_BASE"

VAULT_ENC_KEY=$(openssl rand -hex 16)
echo "VAULT_ENC_KEY=$VAULT_ENC_KEY"

# ClickHouse
CLICKHOUSE_PASSWORD=$(openssl rand -hex 16)
echo "CLICKHOUSE_PASSWORD=$CLICKHOUSE_PASSWORD"
```

Save all these values — you'll need them in Step 5.

---

## Step 4: Generate Supabase API Keys

Supabase API keys are JWTs signed with your `JWT_SECRET`. You need two:

- **ANON_KEY** — public key with `role: anon`
- **SERVICE_ROLE_KEY** — private key with `role: service_role` (bypasses RLS)

### Option A: Using jwt-cli (Node.js)

```bash
npm install -g jwt-cli

# ANON_KEY
jwt sign '{"role":"anon","iss":"supabase","iat":1735689600,"exp":1893456000}' "$JWT_SECRET" --alg HS256

# SERVICE_ROLE_KEY
jwt sign '{"role":"service_role","iss":"supabase","iat":1735689600,"exp":1893456000}' "$JWT_SECRET" --alg HS256
```

### Option B: Using Python

```python
import jwt
secret = "YOUR_JWT_SECRET_HERE"

# anon key
print("ANON_KEY:", jwt.encode(
    {"role": "anon", "iss": "supabase", "iat": 1735689600, "exp": 1893456000},
    secret, algorithm="HS256"
))

# service_role key
print("SERVICE_ROLE_KEY:", jwt.encode(
    {"role": "service_role", "iss": "supabase", "iat": 1735689600, "exp": 1893456000},
    secret, algorithm="HS256"
))
```

### Option C: Supabase Key Generator

Visit https://supabase.com/docs/guides/self-hosting#api-keys and paste your `JWT_SECRET`.

---

## Step 5: Configure `.env`

```bash
cp .env.example .env
nano .env
```

Fill in all required values:

```env
# ─── Required ───────────────────────────────────────────────────
POSTGRES_PASSWORD=<from step 3>
JWT_SECRET=<from step 3>
ANON_KEY=<from step 4>
SERVICE_ROLE_KEY=<from step 4>
REALTIME_SECRET_KEY_BASE=<from step 3>
SECRET_KEY_BASE=<from step 3>
VAULT_ENC_KEY=<from step 3>
CF_API_TOKEN=<your Cloudflare API token>
CLICKHOUSE_PASSWORD=<from step 3>

# ─── Optional (enable as needed) ────────────────────────────────
GITHUB_AUTH_ENABLED=true
GITHUB_CLIENT_ID=<from github.com/settings/developers>
GITHUB_CLIENT_SECRET=<from github.com/settings/developers>

GOOGLE_AUTH_ENABLED=false
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=

SMTP_HOST=smtp.resend.com
SMTP_PORT=587
SMTP_USER=resend
SMTP_PASS=re_xxxxx
```

---

## Step 6: Point DNS

In your Cloudflare dashboard, add DNS records pointing to your server IP:

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | `orchestra-mcp.dev` | `YOUR_SERVER_IP` | Proxied |
| A | `*.orchestra-mcp.dev` | `YOUR_SERVER_IP` | DNS only |

The wildcard `*` covers all subdomains:

| Subdomain | Service |
|-----------|---------|
| `db.orchestra-mcp.dev` | Supabase Studio (admin dashboard) |
| `auth.orchestra-mcp.dev` | GoTrue (authentication) |
| `rest.orchestra-mcp.dev` | PostgREST via Kong (REST API) |
| `realtime.orchestra-mcp.dev` | Supabase Realtime (WebSocket) |
| `storage.orchestra-mcp.dev` | Supabase Storage (file uploads) |
| `edge.orchestra-mcp.dev` | Edge Runtime (Deno functions) |
| `mcp.orchestra-mcp.dev` | Cloud MCP (Streamable HTTP + SSE) |
| `api.orchestra-mcp.dev` | Go Gateway (tunnels, actions, health) |
| `analytics.orchestra-mcp.dev` | ClickHouse (protected, basicauth) |

> **Note:** The wildcard record must be **DNS only** (grey cloud) for Caddy to obtain the TLS certificate via DNS-01 challenge. The root domain can be **Proxied** (orange cloud).

---

## Step 7: Deploy

```bash
chmod +x deploy.sh
./deploy.sh
```

This will:
1. Pull all 16 Docker images
2. Start all services with health checks
3. Run PostgreSQL migrations on first boot (24 migration files)
4. Caddy obtains TLS certificates via Cloudflare DNS-01

First boot takes ~2-3 minutes. Subsequent restarts are ~30 seconds.

---

## Step 8: Verify

```bash
# Check all services are healthy
docker compose ps

# Check specific service logs
docker compose logs supabase-db      # Did migrations run?
docker compose logs caddy             # Did TLS get acquired?
docker compose logs supabase-auth     # Is auth healthy?
docker compose logs clickhouse        # Did analytics schema init?

# Test endpoints
curl -I https://db.orchestra-mcp.dev           # → 200 (Studio)
curl -I https://auth.orchestra-mcp.dev/health  # → 200 (GoTrue)
curl -I https://api.orchestra-mcp.dev/health   # → 200 (Gateway)
curl https://rest.orchestra-mcp.dev/           # → 401 (PostgREST, needs API key)
```

---

## Step 9: Gateway & Next.js Images

The deploy uses pre-built Docker images for the Orchestra services:

```yaml
# In docker-compose.yml
gateway:
  image: ${GATEWAY_IMAGE:-ghcr.io/orchestra-mcp/gateway:latest}
nextjs:
  image: ${NEXTJS_IMAGE:-ghcr.io/orchestra-mcp/web:latest}
```

**Until these images are built** (Phase 3 + Phase 4 of the migration), you can deploy the Supabase stack without them:

1. Comment out the `gateway` and `nextjs` services in `docker-compose.yml`
2. Remove their entries from the `caddy` service's `depends_on`
3. Run `./deploy.sh`

The Supabase infrastructure (DB, Auth, Studio, REST, Realtime, Storage, Edge, ClickHouse) is fully independent and will work on its own.

---

## Common Operations

### Update to latest images
```bash
./deploy.sh --pull-only   # Pull images
./deploy.sh               # Apply updates
```

### Restart all services
```bash
./deploy.sh --restart
```

### View logs
```bash
./deploy.sh --logs                      # All services
docker compose logs -f supabase-db      # Specific service
```

### Stop everything
```bash
./deploy.sh --down
```

### Check status
```bash
./deploy.sh --status
```

### Run a migration manually
```bash
docker compose exec supabase-db psql -U postgres -f /docker-entrypoint-initdb.d/migrations/023_rls_audit_realtime_addendum.sql
```

### Access PostgreSQL directly
```bash
docker compose exec supabase-db psql -U postgres
```

### Access ClickHouse
```bash
docker compose exec clickhouse clickhouse-client --database orchestra_analytics
```

### Backup PostgreSQL
```bash
docker compose exec supabase-db pg_dump -U postgres --no-owner --no-acl postgres > backup_$(date +%Y%m%d).sql
```

### Restore PostgreSQL
```bash
cat backup_20260323.sql | docker compose exec -T supabase-db psql -U postgres
```

---

## Payment Gateway Webhooks

Only two payment gateways are supported. Configure webhooks in each provider:

### GitHub Sponsors
- Webhook URL: `https://api.orchestra-mcp.dev/webhooks/github-sponsors`
- Events: `sponsorship.created`, `sponsorship.cancelled`, `sponsorship.tier_changed`, `sponsorship.pending_tier_change`

### Buy Me a Coffee
- Webhook URL: `https://api.orchestra-mcp.dev/webhooks/buymeacoffee`
- Events: All payment events

---

## Troubleshooting

### Caddy can't get TLS certificate
- Check `CF_API_TOKEN` has `Zone:DNS:Edit` permission for your domain
- Check DNS records exist in Cloudflare
- Check `docker compose logs caddy` for ACME errors

### Migrations didn't run
- Migrations only run on **first boot** when the postgres data volume is empty
- To re-run: `docker compose down -v` (WARNING: deletes all data) then `./deploy.sh`
- Or run manually: `docker compose exec supabase-db psql -U postgres -f /docker-entrypoint-initdb.d/migrations/NNN_filename.sql`

### Service won't start
```bash
docker compose logs <service-name>    # Check error logs
docker compose restart <service-name> # Try restart
```

### PostgREST returns 401
- You need to pass the `apikey` header: `curl -H "apikey: YOUR_ANON_KEY" https://rest.orchestra-mcp.dev/features`

### ClickHouse analytics dashboard (basicauth)
- Set `CLICKHOUSE_ADMIN_USER` and `CLICKHOUSE_ADMIN_HASH` in `.env`
- Generate hash: `caddy hash-password --plaintext YOUR_PASSWORD`
