#!/usr/bin/env bash
# =============================================================================
# Orchestra MCP — One-Command Server Setup
#
# Run on a fresh Ubuntu 22.04+ server:
#   curl -sSL https://raw.githubusercontent.com/orchestra-mcp/deploy/main/setup-server.sh | bash
#
# Or clone first and run:
#   git clone https://github.com/orchestra-mcp/deploy.git /opt/orchestra
#   cd /opt/orchestra && ./setup-server.sh
#
# Interactive: prompts for domain, Cloudflare token, GitHub OAuth, SMTP.
# Generates all secrets automatically.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}[orchestra]${NC} $*"; }
warn() { echo -e "${YELLOW}[orchestra]${NC} $*"; }
err()  { echo -e "${RED}[orchestra]${NC} $*" >&2; }
ask()  { echo -en "${BLUE}[orchestra]${NC} $* "; }

INSTALL_DIR="/opt/orchestra"
REPO_URL="https://github.com/orchestra-mcp/deploy.git"

# ─── Step 1: Install Docker ─────────────────────────────────────────────────

install_docker() {
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        log "Docker + Compose v2 already installed."
        return 0
    fi

    log "Installing Docker..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker
    log "Docker installed successfully."
}

# ─── Step 2: Clone repo ─────────────────────────────────────────────────────

clone_repo() {
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        log "Deploy repo already at $INSTALL_DIR, pulling latest..."
        cd "$INSTALL_DIR"
        git pull --ff-only 2>/dev/null || true
    else
        log "Cloning deploy repo to $INSTALL_DIR..."
        git clone "$REPO_URL" "$INSTALL_DIR" 2>/dev/null || {
            # If git clone fails (private repo), check if files exist locally
            if [ -f "$(dirname "$0")/docker-compose.yml" ]; then
                INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
                log "Using local directory: $INSTALL_DIR"
            else
                err "Failed to clone repo. Clone manually first:"
                err "  git clone $REPO_URL $INSTALL_DIR"
                exit 1
            fi
        }
        cd "$INSTALL_DIR"
    fi
}

# ─── Step 3: Generate secrets ────────────────────────────────────────────────

generate_secrets() {
    log "Generating cryptographic secrets..."

    JWT_SECRET=$(openssl rand -hex 32)
    POSTGRES_PASSWORD=$(openssl rand -hex 24)
    REALTIME_SECRET_KEY_BASE=$(openssl rand -hex 64)
    SECRET_KEY_BASE=$(openssl rand -hex 32)
    VAULT_ENC_KEY=$(openssl rand -hex 16)
    REALTIME_DB_ENC_KEY=$(openssl rand -hex 16)
    CLICKHOUSE_PASSWORD=$(openssl rand -hex 16)

    log "Secrets generated."
}

# ─── Step 4: Generate Supabase JWT keys ──────────────────────────────────────

generate_jwt_keys() {
    log "Generating Supabase API keys (ANON_KEY + SERVICE_ROLE_KEY)..."

    # Use Python (available on most Ubuntu systems) or Node.js
    if command -v python3 &>/dev/null; then
        # Install PyJWT if needed
        python3 -c "import jwt" 2>/dev/null || pip3 install -q PyJWT 2>/dev/null || {
            apt-get install -y -qq python3-pip
            pip3 install -q PyJWT
        }

        ANON_KEY=$(python3 -c "
import jwt
print(jwt.encode({'role':'anon','iss':'supabase','iat':1735689600,'exp':1893456000}, '$JWT_SECRET', algorithm='HS256'))
")
        SERVICE_ROLE_KEY=$(python3 -c "
import jwt
print(jwt.encode({'role':'service_role','iss':'supabase','iat':1735689600,'exp':1893456000}, '$JWT_SECRET', algorithm='HS256'))
")
    elif command -v node &>/dev/null; then
        npm install -g jsonwebtoken 2>/dev/null
        ANON_KEY=$(node -e "
const jwt = require('jsonwebtoken');
console.log(jwt.sign({role:'anon',iss:'supabase',iat:1735689600,exp:1893456000}, '$JWT_SECRET', {algorithm:'HS256'}));
")
        SERVICE_ROLE_KEY=$(node -e "
const jwt = require('jsonwebtoken');
console.log(jwt.sign({role:'service_role',iss:'supabase',iat:1735689600,exp:1893456000}, '$JWT_SECRET', {algorithm:'HS256'}));
")
    else
        err "Neither python3 nor node found. Install one to generate JWT keys."
        err "Or generate keys manually: https://supabase.com/docs/guides/self-hosting#api-keys"
        exit 1
    fi

    log "API keys generated."
}

# ─── Step 5: Interactive config ──────────────────────────────────────────────

collect_config() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Orchestra MCP — Server Configuration${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo ""

    # Domain
    ask "Domain [orchestra-mcp.dev]:"
    read -r DOMAIN
    DOMAIN="${DOMAIN:-orchestra-mcp.dev}"

    # Cloudflare
    ask "Cloudflare API Token (Zone:DNS:Edit):"
    read -r CF_API_TOKEN
    if [ -z "$CF_API_TOKEN" ]; then
        warn "No Cloudflare token — TLS will use HTTP-01 challenge (no wildcards)."
        CF_API_TOKEN=""
    fi

    # GitHub OAuth
    ask "Enable GitHub OAuth? [y/N]:"
    read -r GITHUB_ENABLED
    GITHUB_AUTH_ENABLED="false"
    GITHUB_CLIENT_ID=""
    GITHUB_CLIENT_SECRET=""
    if [[ "$GITHUB_ENABLED" =~ ^[Yy] ]]; then
        GITHUB_AUTH_ENABLED="true"
        ask "  GitHub Client ID:"
        read -r GITHUB_CLIENT_ID
        ask "  GitHub Client Secret:"
        read -r GITHUB_CLIENT_SECRET
    fi

    # Google OAuth
    ask "Enable Google OAuth? [y/N]:"
    read -r GOOGLE_ENABLED
    GOOGLE_AUTH_ENABLED="false"
    GOOGLE_CLIENT_ID=""
    GOOGLE_CLIENT_SECRET=""
    if [[ "$GOOGLE_ENABLED" =~ ^[Yy] ]]; then
        GOOGLE_AUTH_ENABLED="true"
        ask "  Google Client ID:"
        read -r GOOGLE_CLIENT_ID
        ask "  Google Client Secret:"
        read -r GOOGLE_CLIENT_SECRET
    fi

    # SMTP
    ask "SMTP Host (blank to skip email):"
    read -r SMTP_HOST
    SMTP_PORT="587"
    SMTP_USER=""
    SMTP_PASS=""
    SMTP_ADMIN_EMAIL="noreply@${DOMAIN}"
    MAILER_AUTOCONFIRM="true"
    if [ -n "$SMTP_HOST" ]; then
        ask "  SMTP Port [587]:"
        read -r port; SMTP_PORT="${port:-587}"
        ask "  SMTP User:"
        read -r SMTP_USER
        ask "  SMTP Password:"
        read -rs SMTP_PASS; echo ""
        ask "  From Email [noreply@${DOMAIN}]:"
        read -r email; SMTP_ADMIN_EMAIL="${email:-noreply@${DOMAIN}}"
        MAILER_AUTOCONFIRM="false"
    fi

    log "Configuration collected."
}

# ─── Step 6: Write .env ─────────────────────────────────────────────────────

write_env() {
    log "Writing .env..."

    cat > "$INSTALL_DIR/.env" <<ENVEOF
# ═══════════════════════════════════════════════════════════════════
# Orchestra MCP — Generated by setup-server.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Domain: ${DOMAIN}
# ═══════════════════════════════════════════════════════════════════

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
GOTRUE_URI_ALLOW_LIST=https://${DOMAIN}/**,https://db.${DOMAIN}/**

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
SMTP_ADMIN_EMAIL=${SMTP_ADMIN_EMAIL}
SMTP_SENDER_NAME=Orchestra MCP

# ─── Supabase Realtime ───────────────────────────────────────────
REALTIME_DB_ENC_KEY=${REALTIME_DB_ENC_KEY}
REALTIME_SECRET_KEY_BASE=${REALTIME_SECRET_KEY_BASE}

# ─── Cloudflare ──────────────────────────────────────────────────
CF_API_TOKEN=${CF_API_TOKEN}

# ─── Supabase Dashboard ─────────────────────────────────────────
DASHBOARD_USERNAME=supabase
DASHBOARD_PASSWORD=$(openssl rand -hex 12)

# ─── ClickHouse ──────────────────────────────────────────────────
CLICKHOUSE_USER=orchestra
CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
CLICKHOUSE_ADMIN_USER=admin
CLICKHOUSE_ADMIN_HASH=$(docker run --rm caddy:2.9-alpine caddy hash-password --plaintext "${CLICKHOUSE_PASSWORD}" 2>/dev/null || echo "GENERATE_ME")

# ─── Supavisor ───────────────────────────────────────────────────
SECRET_KEY_BASE=${SECRET_KEY_BASE}
VAULT_ENC_KEY=${VAULT_ENC_KEY}

# ─── Orchestra Services ─────────────────────────────────────────
# GATEWAY_IMAGE=ghcr.io/orchestra-mcp/gateway:latest
# NEXTJS_IMAGE=ghcr.io/orchestra-mcp/web:latest
ENVEOF

    chmod 600 "$INSTALL_DIR/.env"
    log ".env written (permissions: 600)."
}

# ─── Step 7: Update domain in Caddyfile ──────────────────────────────────────

update_domain() {
    if [ "$DOMAIN" != "orchestra-mcp.dev" ]; then
        log "Updating domain to ${DOMAIN} in Caddyfile..."
        sed -i "s/orchestra-mcp\.dev/${DOMAIN}/g" "$INSTALL_DIR/Caddyfile"
        log "Domain updated in Caddyfile."
    fi
}

# ─── Step 8: Deploy ─────────────────────────────────────────────────────────

deploy() {
    log "Pulling Docker images (this may take a few minutes)..."
    cd "$INSTALL_DIR"
    docker compose pull

    log "Starting services..."
    docker compose up -d

    log "Waiting for services to initialize..."
    sleep 10

    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Orchestra MCP — Deployment Complete!${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo ""
    docker compose ps
    echo ""
    log "Services:"
    log "  Frontend:  https://${DOMAIN}"
    log "  Studio:    https://db.${DOMAIN}"
    log "  Auth:      https://auth.${DOMAIN}"
    log "  REST API:  https://rest.${DOMAIN}"
    log "  Realtime:  https://realtime.${DOMAIN}"
    log "  Storage:   https://storage.${DOMAIN}"
    log "  Edge:      https://edge.${DOMAIN}"
    log "  MCP:       https://mcp.${DOMAIN}"
    log "  Gateway:   https://api.${DOMAIN}"
    log "  Analytics: https://analytics.${DOMAIN}"
    echo ""
    log "Manage:"
    log "  cd $INSTALL_DIR"
    log "  ./deploy.sh --status    # Check status"
    log "  ./deploy.sh --logs      # View logs"
    log "  ./deploy.sh --restart   # Restart services"
    log "  ./deploy.sh             # Pull & redeploy"
    echo ""
    warn "IMPORTANT: Set up DNS records in Cloudflare if not done already."
    warn "  A record: ${DOMAIN}     → YOUR_SERVER_IP (Proxied)"
    warn "  A record: *.${DOMAIN}   → YOUR_SERVER_IP (DNS only)"
    echo ""
    log "Secrets stored in: $INSTALL_DIR/.env (chmod 600)"
    log "Backup your .env file — it contains all credentials!"
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Orchestra MCP — One-Command Server Setup${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo ""

    # Check root
    if [ "$(id -u)" -ne 0 ]; then
        err "This script must be run as root (sudo)."
        err "Usage: sudo ./setup-server.sh"
        exit 1
    fi

    install_docker
    clone_repo
    generate_secrets
    generate_jwt_keys
    collect_config
    write_env
    update_domain
    deploy
}

main "$@"
