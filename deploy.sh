#!/usr/bin/env bash
# =============================================================================
# Orchestra MCP — Deploy Script
#
# Usage:
#   ./deploy.sh              # First-time deploy or update
#   ./deploy.sh --pull-only  # Just pull latest images
#   ./deploy.sh --restart    # Restart all services
#   ./deploy.sh --logs       # Tail logs
# =============================================================================

set -euo pipefail
cd "$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log()  { echo -e "${GREEN}[deploy]${NC} $*"; }
warn() { echo -e "${YELLOW}[deploy]${NC} $*"; }
err()  { echo -e "${RED}[deploy]${NC} $*" >&2; }
ask()  { echo -en "${BLUE}[deploy]${NC} $* "; }
info() { echo -e "${DIM}           $*${NC}"; }

prompt_password() {
    local label="$1"
    local varname="$2"
    local length="${3:-32}"

    ask "${label} (Enter value or press Enter to auto-generate):"
    local value
    read -rs value
    echo ""

    if [ -z "$value" ]; then
        value=$(openssl rand -hex "$length")
        log "  → Auto-generated (${length}-byte hex)"
    else
        log "  → Using your value"
    fi

    eval "$varname='$value'"
}

prompt_required() {
    local label="$1"
    local varname="$2"

    while true; do
        ask "$label"
        local value
        read -r value
        if [ -n "$value" ]; then
            eval "$varname='$value'"
            return 0
        fi
        warn "This field is required."
    done
}

prompt_optional() {
    local label="$1"
    local varname="$2"
    local default="${3:-}"

    ask "$label"
    local value
    read -r value
    eval "$varname='${value:-$default}'"
}

# Check prerequisites
command -v docker >/dev/null 2>&1 || { err "docker is required but not installed."; exit 1; }
docker compose version >/dev/null 2>&1 || { err "docker compose v2 is required."; exit 1; }

# ── Interactive .env creation when missing ─────────────────────────────────
create_env_interactive() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Orchestra MCP — First-Time Setup${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo ""
    info "No .env file found. Let's create one."
    info "Secrets can be auto-generated — just press Enter."
    echo ""

    # ── Cloudflare (required for wildcard TLS) ────────────────────────
    echo -e "${CYAN}─── Cloudflare ───────────────────────────────────${NC}"
    info "Required for wildcard TLS certs (*.orchestra-mcp.dev)."
    info "Create at: https://dash.cloudflare.com/profile/api-tokens"
    info "Token needs Zone:DNS:Edit permission."
    prompt_required "Cloudflare API Token:" CF_API_TOKEN
    echo ""

    # ── Passwords & Secrets ───────────────────────────────────────────
    echo -e "${CYAN}─── Passwords & Secrets ──────────────────────────${NC}"
    info "Press Enter to auto-generate secure random values."
    echo ""

    prompt_password "PostgreSQL Password" POSTGRES_PASSWORD 24
    prompt_password "JWT Secret (HMAC)" JWT_SECRET 32
    prompt_password "Realtime Secret Key Base" REALTIME_SECRET_KEY_BASE 64
    prompt_password "Supavisor Secret Key Base" SECRET_KEY_BASE 32
    prompt_password "Vault Encryption Key" VAULT_ENC_KEY 16
    prompt_password "Realtime DB Encryption Key" REALTIME_DB_ENC_KEY 16
    prompt_password "ClickHouse Password" CLICKHOUSE_PASSWORD 16
    echo ""

    # ── Supabase Studio ───────────────────────────────────────────────
    echo -e "${CYAN}─── Supabase Studio (Dashboard) ──────────────────${NC}"
    prompt_optional "Studio Username [supabase]:" DASHBOARD_USERNAME "supabase"
    prompt_password "Studio Password" DASHBOARD_PASSWORD 12
    if ! echo "$DASHBOARD_PASSWORD" | grep -q '[a-zA-Z]'; then
        DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD}aZ"
    fi
    echo ""

    # ── OAuth (optional) ──────────────────────────────────────────────
    echo -e "${CYAN}─── OAuth Providers (optional) ───────────────────${NC}"
    GITHUB_AUTH_ENABLED="false"
    GITHUB_CLIENT_ID=""
    GITHUB_CLIENT_SECRET=""
    GOOGLE_AUTH_ENABLED="false"
    GOOGLE_CLIENT_ID=""
    GOOGLE_CLIENT_SECRET=""

    ask "Enable GitHub OAuth? [y/N]:"
    read -r gh_enabled
    if [[ "${gh_enabled:-}" =~ ^[Yy] ]]; then
        GITHUB_AUTH_ENABLED="true"
        prompt_required "  GitHub Client ID:" GITHUB_CLIENT_ID
        prompt_required "  GitHub Client Secret:" GITHUB_CLIENT_SECRET
    fi

    ask "Enable Google OAuth? [y/N]:"
    read -r g_enabled
    if [[ "${g_enabled:-}" =~ ^[Yy] ]]; then
        GOOGLE_AUTH_ENABLED="true"
        prompt_required "  Google Client ID:" GOOGLE_CLIENT_ID
        prompt_required "  Google Client Secret:" GOOGLE_CLIENT_SECRET
    fi
    echo ""

    # ── SMTP (optional) ──────────────────────────────────────────────
    echo -e "${CYAN}─── SMTP / Email (optional) ──────────────────────${NC}"
    info "Leave blank to auto-confirm users without email."
    SMTP_HOST=""
    SMTP_PORT="587"
    SMTP_USER=""
    SMTP_PASS=""
    MAILER_AUTOCONFIRM="true"

    ask "SMTP Host (blank to skip):"
    read -r SMTP_HOST
    if [ -n "$SMTP_HOST" ]; then
        prompt_optional "  SMTP Port [587]:" SMTP_PORT "587"
        prompt_optional "  SMTP User:" SMTP_USER ""
        ask "  SMTP Password:"
        read -rs SMTP_PASS
        echo ""
        MAILER_AUTOCONFIRM="false"
    fi
    echo ""

    # ── Edge Functions (optional) ─────────────────────────────────────
    echo -e "${CYAN}─── Edge Functions (optional) ────────────────────${NC}"
    prompt_password "MCP JWT Secret" MCP_JWT_SECRET 32
    prompt_optional "BMaC Webhook Secret (blank to skip):" BMAC_WEBHOOK_SECRET ""
    echo ""

    # ── Generate Supabase JWT keys ────────────────────────────────────
    log "Generating Supabase API keys..."
    if command -v python3 &>/dev/null; then
        python3 -c "import jwt" 2>/dev/null || pip3 install -q PyJWT 2>/dev/null || true
        ANON_KEY=$(python3 -c "
import jwt
print(jwt.encode({'role':'anon','iss':'supabase','iat':1735689600,'exp':1893456000}, '$JWT_SECRET', algorithm='HS256'))
" 2>/dev/null || echo "GENERATE_ME")
        SERVICE_ROLE_KEY=$(python3 -c "
import jwt
print(jwt.encode({'role':'service_role','iss':'supabase','iat':1735689600,'exp':1893456000}, '$JWT_SECRET', algorithm='HS256'))
" 2>/dev/null || echo "GENERATE_ME")
    elif command -v node &>/dev/null; then
        ANON_KEY=$(node -e "
const crypto = require('crypto');
const header = Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
const payload = Buffer.from(JSON.stringify({role:'anon',iss:'supabase',iat:1735689600,exp:1893456000})).toString('base64url');
const sig = crypto.createHmac('sha256','$JWT_SECRET').update(header+'.'+payload).digest('base64url');
console.log(header+'.'+payload+'.'+sig);
" 2>/dev/null || echo "GENERATE_ME")
        SERVICE_ROLE_KEY=$(node -e "
const crypto = require('crypto');
const header = Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
const payload = Buffer.from(JSON.stringify({role:'service_role',iss:'supabase',iat:1735689600,exp:1893456000})).toString('base64url');
const sig = crypto.createHmac('sha256','$JWT_SECRET').update(header+'.'+payload).digest('base64url');
console.log(header+'.'+payload+'.'+sig);
" 2>/dev/null || echo "GENERATE_ME")
    else
        warn "Cannot auto-generate JWT keys (no python3 or node)."
        warn "Generate manually: https://supabase.com/docs/guides/self-hosting#api-keys"
        ANON_KEY="GENERATE_ME"
        SERVICE_ROLE_KEY="GENERATE_ME"
    fi

    if [ "$ANON_KEY" != "GENERATE_ME" ]; then
        log "API keys generated."
    fi

    # ── Generate Caddy password hashes ────────────────────────────────
    local studio_hash ch_admin_hash
    studio_hash=$(docker run --rm caddy:2.9-alpine caddy hash-password --plaintext "${DASHBOARD_PASSWORD}" 2>/dev/null || echo 'GENERATE_WITH: docker run --rm caddy:2.9-alpine caddy hash-password --plaintext "YOUR_PASSWORD"')
    ch_admin_hash=$(docker run --rm caddy:2.9-alpine caddy hash-password --plaintext "${CLICKHOUSE_PASSWORD}" 2>/dev/null || echo 'GENERATE_ME')

    # ── Write .env ────────────────────────────────────────────────────
    log "Writing .env file..."

    cat > .env <<ENVEOF
# Orchestra MCP — Generated by deploy.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)

# ─── PostgreSQL ────────────────────────────────────────────────────
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=postgres

# ─── JWT / Supabase Auth ──────────────────────────────────────────
JWT_SECRET=${JWT_SECRET}
JWT_EXPIRY=3600
ANON_KEY=${ANON_KEY}
SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}

# ─── GoTrue Settings ─────────────────────────────────────────────
GOTRUE_MAILER_AUTOCONFIRM=${MAILER_AUTOCONFIRM}
GOTRUE_SMS_AUTOCONFIRM=true
GOTRUE_DISABLE_SIGNUP=false
GOTRUE_URI_ALLOW_LIST=https://orchestra-mcp.dev/**,https://db.orchestra-mcp.dev/**

# ─── OAuth: GitHub ───────────────────────────────────────────────
GITHUB_AUTH_ENABLED=${GITHUB_AUTH_ENABLED}
GITHUB_CLIENT_ID=${GITHUB_CLIENT_ID}
GITHUB_CLIENT_SECRET=${GITHUB_CLIENT_SECRET}

# ─── OAuth: Google ───────────────────────────────────────────────
GOOGLE_AUTH_ENABLED=${GOOGLE_AUTH_ENABLED}
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}

# ─── SMTP ────────────────────────────────────────────────────────
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_USER=${SMTP_USER}
SMTP_PASS=${SMTP_PASS}
SMTP_ADMIN_EMAIL=noreply@orchestra-mcp.dev
SMTP_SENDER_NAME=Orchestra MCP

# ─── Supabase Realtime ───────────────────────────────────────────
REALTIME_DB_ENC_KEY=${REALTIME_DB_ENC_KEY}
REALTIME_SECRET_KEY_BASE=${REALTIME_SECRET_KEY_BASE}

# ─── Cloudflare ──────────────────────────────────────────────────
CF_API_TOKEN=${CF_API_TOKEN}

# ─── Supabase Dashboard (Studio) ────────────────────────────────
DASHBOARD_USERNAME=${DASHBOARD_USERNAME}
DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}
DASHBOARD_PASSWORD_HASH=${studio_hash}

# ─── ClickHouse ──────────────────────────────────────────────────
CLICKHOUSE_USER=orchestra
CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
CLICKHOUSE_ADMIN_USER=admin
CLICKHOUSE_ADMIN_HASH=${ch_admin_hash}

# ─── Supavisor ───────────────────────────────────────────────────
SECRET_KEY_BASE=${SECRET_KEY_BASE}
VAULT_ENC_KEY=${VAULT_ENC_KEY}

# ─── Edge Functions ──────────────────────────────────────────────
MCP_JWT_SECRET=${MCP_JWT_SECRET}
BMAC_WEBHOOK_SECRET=${BMAC_WEBHOOK_SECRET}

# ─── Orchestra Services ─────────────────────────────────────────
ALLOWED_ORIGINS=https://orchestra-mcp.dev,https://mcp.orchestra-mcp.dev
WEB_API_BASE_URL=https://api.orchestra-mcp.dev
# GATEWAY_IMAGE=ghcr.io/orchestra-mcp/gateway:latest
# NEXTJS_IMAGE=ghcr.io/orchestra-mcp/web:latest
ENVEOF

    chmod 600 .env
    log ".env created (permissions: 600)"
    echo ""
    echo -e "${BOLD}  Credentials Summary:${NC}"
    log "  Studio Login:     ${DASHBOARD_USERNAME} / ${DASHBOARD_PASSWORD}"
    log "  PostgreSQL:       postgres / (see .env)"
    log "  ClickHouse:       orchestra / (see .env)"
    if [ "$ANON_KEY" = "GENERATE_ME" ]; then
        warn "  ANON_KEY and SERVICE_ROLE_KEY need manual generation!"
        warn "  See: https://supabase.com/docs/guides/self-hosting#api-keys"
    fi
    echo ""
    warn "IMPORTANT: Backup your .env — it contains all credentials!"
    echo ""
}

if [ ! -f .env ]; then
    create_env_interactive
fi

case "${1:-}" in
    --pull-only)
        log "Pulling latest images..."
        docker compose pull
        log "Done. Run './deploy.sh' to apply updates."
        ;;
    --restart)
        log "Restarting all services..."
        docker compose restart
        log "Done."
        ;;
    --logs)
        docker compose logs -f --tail=100
        ;;
    --down)
        warn "Stopping all services..."
        docker compose down
        log "All services stopped."
        ;;
    --status)
        docker compose ps
        ;;
    *)
        log "Pulling latest images..."
        docker compose pull

        log "Starting services..."
        docker compose up -d

        log "Waiting for health checks..."
        sleep 5

        log "Service status:"
        docker compose ps

        echo ""
        log "Deploy complete!"
        log "  Studio:    https://db.orchestra-mcp.dev"
        log "  Auth:      https://auth.orchestra-mcp.dev"
        log "  REST API:  https://rest.orchestra-mcp.dev"
        log "  Realtime:  https://realtime.orchestra-mcp.dev"
        log "  Storage:   https://storage.orchestra-mcp.dev"
        log "  Edge:      https://edge.orchestra-mcp.dev"
        log "  MCP:       https://mcp.orchestra-mcp.dev"
        log "  Gateway:   https://api.orchestra-mcp.dev"
        log "  Frontend:  https://orchestra-mcp.dev"
        log "  Analytics: https://analytics.orchestra-mcp.dev"
        ;;
esac
