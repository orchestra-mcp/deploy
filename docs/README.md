# Orchestra MCP — Server Deployment Guide

Step-by-step instructions to deploy the full Orchestra MCP platform on a fresh server.

---

## Prerequisites

- A Linux server (Ubuntu 22.04+ recommended) with root/sudo access
- A domain pointed to your server (e.g. `orchestra-mcp.dev`)
- A Cloudflare account with the domain zone configured (for wildcard TLS)
- At least 4GB RAM, 2 vCPUs, 40GB disk

---

## Option A: One-Command Install (Recommended)

SSH into your server and run:

```bash
curl -fsSL https://raw.githubusercontent.com/orchestra-mcp/deploy/master/setup-server.sh | sudo bash
```

The script will:
1. Install Docker + Docker Compose v2 (if not present)
2. Clone the deploy repo to `/opt/orchestra`
3. Walk you through interactive configuration:
   - **Domain** — your custom domain or default `orchestra-mcp.dev`
   - **Cloudflare API Token** — for wildcard TLS certificates
   - **Passwords & Secrets** — for each one, enter your own or press Enter to auto-generate
   - **Studio Dashboard** — username and password for `db.your-domain.com`
   - **OAuth Providers** — optionally enable GitHub and/or Google OAuth
   - **SMTP** — optionally configure email sending
4. Generate Supabase API keys (ANON_KEY + SERVICE_ROLE_KEY)
5. Write `.env` with all secrets (permissions 600)
6. Pull and start all 16 Docker containers
7. Print all service URLs and credentials

After completion, your stack is live. Skip to [Step: Point DNS](#point-dns).

---

## Option B: Manual Setup

### Step 1: Install Docker

```bash
# Ubuntu 22.04+
curl -fsSL https://get.docker.com | sh
systemctl enable docker && systemctl start docker
```

### Step 2: Clone the Deploy Repo

```bash
git clone https://github.com/orchestra-mcp/deploy.git /opt/orchestra
cd /opt/orchestra
```

### Step 3: Configure Environment

```bash
cp .env.example .env
nano .env
```

Fill in all required values. For each secret, you can generate secure random values:

```bash
# Passwords (enter your own or generate)
openssl rand -hex 24    # PostgreSQL password
openssl rand -hex 32    # JWT secret
openssl rand -hex 64    # Realtime secret key base
openssl rand -hex 32    # Supavisor secret key base
openssl rand -hex 16    # Vault encryption key
openssl rand -hex 16    # Realtime DB encryption key
openssl rand -hex 16    # ClickHouse password
openssl rand -hex 12    # Studio dashboard password (must include a letter)
```

### Step 4: Generate Supabase API Keys

Supabase API keys are JWTs signed with your `JWT_SECRET`. You need two:

- **ANON_KEY** — public key with `role: anon`
- **SERVICE_ROLE_KEY** — private key with `role: service_role` (bypasses RLS)

**Using Python:**
```bash
pip3 install PyJWT
python3 -c "
import jwt
secret = 'YOUR_JWT_SECRET_HERE'
print('ANON_KEY:', jwt.encode({'role':'anon','iss':'supabase','iat':1735689600,'exp':1893456000}, secret, algorithm='HS256'))
print('SERVICE_ROLE_KEY:', jwt.encode({'role':'service_role','iss':'supabase','iat':1735689600,'exp':1893456000}, secret, algorithm='HS256'))
"
```

**Using the Supabase Key Generator:**
Visit https://supabase.com/docs/guides/self-hosting#api-keys and paste your `JWT_SECRET`.

### Step 5: Generate Caddy Password Hashes

Studio and ClickHouse are protected by Caddy basic auth. Generate bcrypt hashes:

```bash
# Studio password hash
docker run --rm caddy:2.9-alpine caddy hash-password --plaintext "YOUR_STUDIO_PASSWORD"
# → paste result as DASHBOARD_PASSWORD_HASH in .env

# ClickHouse admin hash
docker run --rm caddy:2.9-alpine caddy hash-password --plaintext "YOUR_CLICKHOUSE_PASSWORD"
# → paste result as CLICKHOUSE_ADMIN_HASH in .env
```

### Step 6: Deploy

```bash
docker compose up -d
```

---

## Point DNS

In your Cloudflare dashboard, add DNS records pointing to your server IP:

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | `orchestra-mcp.dev` | `YOUR_SERVER_IP` | Proxied |
| A | `*.orchestra-mcp.dev` | `YOUR_SERVER_IP` | DNS only |

The wildcard `*` covers all subdomains:

| Subdomain | Service | Auth |
|-----------|---------|------|
| `db.orchestra-mcp.dev` | Supabase Studio (dashboard) | Basic auth (DASHBOARD_USERNAME/PASSWORD) |
| `auth.orchestra-mcp.dev` | GoTrue (authentication) | Public |
| `rest.orchestra-mcp.dev` | PostgREST via Kong (REST API) | API key header |
| `realtime.orchestra-mcp.dev` | Supabase Realtime (WebSocket) | JWT |
| `storage.orchestra-mcp.dev` | Supabase Storage (file uploads) | JWT |
| `edge.orchestra-mcp.dev` | Edge Runtime (Deno functions) | JWT |
| `mcp.orchestra-mcp.dev` | Gateway — MCP transport (Streamable HTTP + SSE) | JWT |
| `api.orchestra-mcp.dev` | Gateway — REST API (tunnels, actions, health) | JWT |
| `analytics.orchestra-mcp.dev` | ClickHouse analytics | Basic auth (CLICKHOUSE_ADMIN) |

> **Note:** The wildcard record must be **DNS only** (grey cloud) for Caddy to obtain the TLS certificate via DNS-01 challenge. The root domain can be **Proxied** (orange cloud).

---

## Verify Deployment

```bash
# Check all services are healthy
docker compose ps

# Check specific service logs
docker compose logs supabase-db      # Did migrations run?
docker compose logs caddy             # Did TLS get acquired?
docker compose logs supabase-auth     # Is auth healthy?
docker compose logs clickhouse        # Did analytics schema init?

# Test endpoints
curl -I https://orchestra-mcp.dev               # → 200 (Next.js)
curl -I https://db.orchestra-mcp.dev            # → 401 (Studio — needs basicauth)
curl -u supabase:yourpass https://db.orchestra-mcp.dev  # → 200 (Studio)
curl -I https://auth.orchestra-mcp.dev/health   # → 200 (GoTrue)
curl -I https://api.orchestra-mcp.dev/health    # → 200 (Gateway)
curl https://rest.orchestra-mcp.dev/            # → 401 (PostgREST — needs API key)
```

---

## Studio Login

Supabase Studio at `db.orchestra-mcp.dev` is protected with two layers:

1. **Caddy basic auth** — browser prompts for username/password before reaching Studio
2. **Studio internal auth** — uses DASHBOARD_USERNAME and DASHBOARD_PASSWORD env vars

Both use the same credentials set during setup. To change the password:

```bash
cd /opt/orchestra

# 1. Update the password in .env
nano .env
# Change DASHBOARD_PASSWORD=new_password_with_letters

# 2. Regenerate the Caddy bcrypt hash
docker run --rm caddy:2.9-alpine caddy hash-password --plaintext "new_password_with_letters"
# Copy the hash and update DASHBOARD_PASSWORD_HASH in .env

# 3. Restart
docker compose up -d --force-recreate
```

> **Important:** Studio password must include at least one letter (not numbers/special chars only).

---

## Gateway & Next.js Images

The deploy uses pre-built Docker images for Orchestra services. The **gateway** is a unified Go binary
(source: `apps/gateway/`) that handles both the REST API (`api.`) and MCP transport (`mcp.`) subdomains:

```yaml
gateway:
  image: ${GATEWAY_IMAGE:-ghcr.io/orchestra-mcp/gateway:latest}
nextjs:
  image: ${NEXTJS_IMAGE:-ghcr.io/orchestra-mcp/web:latest}
```

**Until these images are built** (Phase 3 + Phase 4 of the migration), deploy the Supabase stack without them:

1. Comment out the `gateway` and `nextjs` services in `docker-compose.yml`
2. Remove their entries from the `caddy` service's `depends_on`
3. Run `docker compose up -d`

The Supabase infrastructure (DB, Auth, Studio, REST, Realtime, Storage, Edge, ClickHouse) is fully independent.

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

## CI/CD Deployment

Deploy is triggered **manually** from GitHub Actions (no auto-deploy on push):

1. Go to **Actions > Deploy to Production**
2. Click **Run workflow**
3. Optionally specify a single service to restart (e.g., `supabase-db`)

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `DEPLOY_HOST` | Server IP or hostname |
| `DEPLOY_USER` | SSH username (root or deploy) |
| `DEPLOY_SSH_KEY` | Ed25519 private key (no passphrase) |
| `DEPLOY_KNOWN_HOSTS` | Server SSH host key |

### Generate SSH Deploy Key

```bash
# On your local machine
ssh-keygen -t ed25519 -C "orchestra-deploy" -f ~/.ssh/orchestra_deploy -N ""
ssh-copy-id -i ~/.ssh/orchestra_deploy.pub root@YOUR_SERVER_IP

# Private key → DEPLOY_SSH_KEY secret
cat ~/.ssh/orchestra_deploy

# Known hosts → DEPLOY_KNOWN_HOSTS secret
ssh-keyscan YOUR_SERVER_IP
```

### Deploy Flow

```
Manual trigger → GitHub Actions
  → rsync files to server (excludes .env, .git, logs)
  → docker compose pull
  → docker compose up -d
  → Health check verification
  → Cleanup old Docker images (>7 days)
```

---

## Payment Gateway Webhooks

Only two payment gateways are supported:

### GitHub Sponsors
- Webhook URL: `https://api.orchestra-mcp.dev/webhooks/github-sponsors`
- Events: `sponsorship.created`, `sponsorship.cancelled`, `sponsorship.tier_changed`

### Buy Me a Coffee
- Webhook URL: `https://api.orchestra-mcp.dev/webhooks/buymeacoffee`
- Events: All payment events

---

## Troubleshooting

### Caddy can't get TLS certificate
- Check `CF_API_TOKEN` has `Zone:DNS:Edit` permission for your domain
- Check DNS records exist in Cloudflare
- Check `docker compose logs caddy` for ACME errors

### Studio returns 401
- Browser prompts for basic auth credentials (DASHBOARD_USERNAME/DASHBOARD_PASSWORD)
- If you forgot the password, check `/opt/orchestra/.env`
- If DASHBOARD_PASSWORD_HASH is wrong, regenerate: `docker run --rm caddy:2.9-alpine caddy hash-password --plaintext "your_password"`

### Migrations didn't run
- Migrations only run on **first boot** when the postgres data volume is empty
- To re-run: `docker compose down -v` (WARNING: deletes all data) then `docker compose up -d`
- Or run manually: `docker compose exec supabase-db psql -U postgres -f /docker-entrypoint-initdb.d/migrations/NNN_filename.sql`

### Service won't start
```bash
docker compose logs <service-name>    # Check error logs
docker compose restart <service-name> # Try restart
```

### PostgREST returns 401
- Pass the `apikey` header: `curl -H "apikey: YOUR_ANON_KEY" https://rest.orchestra-mcp.dev/features`

### ClickHouse returns 401
- Protected by basic auth: `curl -u admin:your_password https://analytics.orchestra-mcp.dev/`
