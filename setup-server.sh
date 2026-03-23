#!/usr/bin/env bash
# =============================================================================
# Orchestra MCP — One-Command Server Setup
#
# Run on a fresh Ubuntu 22.04+ server:
#   curl -fsSL https://raw.githubusercontent.com/orchestra-mcp/deploy/master/setup-server.sh | sudo bash
#
# Installs Docker, clones the deploy repo, generates all secrets,
# configures interactively, and deploys the full stack.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log()  { echo -e "${GREEN}[orchestra]${NC} $*"; }
warn() { echo -e "${YELLOW}[orchestra]${NC} $*"; }
err()  { echo -e "${RED}[orchestra]${NC} $*" >&2; }
ask()  { echo -en "${BLUE}[orchestra]${NC} $* "; }
info() { echo -e "${DIM}             $*${NC}"; }

# When piped via curl | sh, stdin is the script itself.
# Redirect interactive reads from /dev/tty so prompts work.
prompt() {
    ask "$1"
    read -r "$2" </dev/tty
}

prompt_secret() {
    ask "$1"
    read -rs "$2" </dev/tty
    echo ""
}

# Prompt for a password/token: user can enter their own or press Enter to auto-generate
prompt_password() {
    local label="$1"
    local varname="$2"
    local length="${3:-32}"

    ask "${label} (Enter your own or press Enter to auto-generate):"
    local value
    read -rs value </dev/tty
    echo ""

    if [ -z "$value" ]; then
        value=$(openssl rand -hex "$length")
        log "  → Auto-generated (${length}-byte hex)"
    else
        log "  → Using your custom value"
    fi

    eval "$varname='$value'"
}

# Prompt for a token: user must provide it or skip
prompt_token() {
    local label="$1"
    local varname="$2"
    local required="${3:-false}"

    prompt "$label"
    local value
    eval "value=\"\${$varname:-}\""

    if [ -z "$value" ] && [ "$required" = "true" ]; then
        err "This token is required. Cannot continue without it."
        exit 1
    fi
}

INSTALL_DIR="/opt/orchestra"
REPO_URL="https://github.com/orchestra-mcp/deploy.git"
REPO_BRANCH="master"

# ─── Step 1: Install Docker ─────────────────────────────────────────────────

install_docker() {
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        log "Docker + Compose v2 already installed."
        return 0
    fi

    log "Installing Docker..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release git

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
        git clone -b "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
    fi
}

# ─── Step 3: Interactive config ──────────────────────────────────────────────

collect_config() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Orchestra MCP — Server Configuration${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo ""

    # ── Domain ──────────────────────────────────────────────────────────
    echo -e "${CYAN}─── Domain ───────────────────────────────────────${NC}"
    prompt "Domain [orchestra-mcp.dev]:" DOMAIN
    DOMAIN="${DOMAIN:-orchestra-mcp.dev}"
    echo ""

    # ── Cloudflare ──────────────────────────────────────────────────────
    echo -e "${CYAN}─── Cloudflare (TLS) ─────────────────────────────${NC}"
    info "Required for wildcard TLS certs (*.${DOMAIN})."
    info "Create at: https://dash.cloudflare.com/profile/api-tokens"
    info "Token needs Zone:DNS:Edit permission for your domain."
    prompt "Cloudflare API Token:" CF_API_TOKEN
    if [ -z "${CF_API_TOKEN:-}" ]; then
        warn "No Cloudflare token — TLS will use HTTP-01 challenge (no wildcards)."
        CF_API_TOKEN=""
    fi
    echo ""

    # ── Passwords & Secrets ─────────────────────────────────────────────
    echo -e "${CYAN}─── Passwords & Secrets ──────────────────────────${NC}"
    info "For each secret below, enter your own value or press Enter"
    info "to auto-generate a secure random password."
    echo ""

    prompt_password "PostgreSQL Password" POSTGRES_PASSWORD 24
    prompt_password "JWT Secret (HMAC)" JWT_SECRET 32
    prompt_password "Realtime Secret Key Base" REALTIME_SECRET_KEY_BASE 64
    prompt_password "Supavisor Secret Key Base" SECRET_KEY_BASE 32
    prompt_password "Vault Encryption Key" VAULT_ENC_KEY 16
    prompt_password "Realtime DB Encryption Key" REALTIME_DB_ENC_KEY 16
    prompt_password "ClickHouse Password" CLICKHOUSE_PASSWORD 16
    echo ""

    # ── Studio Dashboard ────────────────────────────────────────────────
    echo -e "${CYAN}─── Supabase Studio (Dashboard) ──────────────────${NC}"
    info "Studio is protected with basic auth at db.${DOMAIN}"
    info "Password must include at least one letter."
    echo ""

    prompt "Studio Username [supabase]:" DASHBOARD_USERNAME
    DASHBOARD_USERNAME="${DASHBOARD_USERNAME:-supabase}"

    prompt_password "Studio Password" DASHBOARD_PASSWORD 12
    # Ensure at least one letter (Supabase Studio requirement)
    if ! echo "$DASHBOARD_PASSWORD" | grep -q '[a-zA-Z]'; then
        DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD}aZ"
        warn "Added letters to password (Studio requires at least one letter)."
    fi
    echo ""

    # ── GitHub OAuth ────────────────────────────────────────────────────
    echo -e "${CYAN}─── OAuth Providers ──────────────────────────────${NC}"
    prompt "Enable GitHub OAuth? [y/N]:" GITHUB_ENABLED
    GITHUB_AUTH_ENABLED="false"
    GITHUB_CLIENT_ID=""
    GITHUB_CLIENT_SECRET=""
    if [[ "${GITHUB_ENABLED:-}" =~ ^[Yy] ]]; then
        GITHUB_AUTH_ENABLED="true"
        info "Create at: https://github.com/settings/developers"
        prompt "  GitHub Client ID:" GITHUB_CLIENT_ID
        prompt "  GitHub Client Secret:" GITHUB_CLIENT_SECRET
    fi

    # ── Google OAuth ────────────────────────────────────────────────────
    prompt "Enable Google OAuth? [y/N]:" GOOGLE_ENABLED
    GOOGLE_AUTH_ENABLED="false"
    GOOGLE_CLIENT_ID=""
    GOOGLE_CLIENT_SECRET=""
    if [[ "${GOOGLE_ENABLED:-}" =~ ^[Yy] ]]; then
        GOOGLE_AUTH_ENABLED="true"
        info "Create at: https://console.cloud.google.com/apis/credentials"
        prompt "  Google Client ID:" GOOGLE_CLIENT_ID
        prompt "  Google Client Secret:" GOOGLE_CLIENT_SECRET
    fi
    echo ""

    # ── SMTP ────────────────────────────────────────────────────────────
    echo -e "${CYAN}─── SMTP (Email) ─────────────────────────────────${NC}"
    info "For email verification, password reset, invites."
    info "Leave blank to auto-confirm users (no email needed)."
    prompt "SMTP Host (blank to skip):" SMTP_HOST
    SMTP_PORT="587"
    SMTP_USER=""
    SMTP_PASS=""
    SMTP_ADMIN_EMAIL="noreply@${DOMAIN}"
    MAILER_AUTOCONFIRM="true"
    if [ -n "${SMTP_HOST:-}" ]; then
        prompt "  SMTP Port [587]:" port
        SMTP_PORT="${port:-587}"
        prompt "  SMTP User:" SMTP_USER
        prompt_secret "  SMTP Password:" SMTP_PASS
        prompt "  From Email [noreply@${DOMAIN}]:" email
        SMTP_ADMIN_EMAIL="${email:-noreply@${DOMAIN}}"
        MAILER_AUTOCONFIRM="false"
    fi
    echo ""

    log "Configuration collected."
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

# ─── Step 5: Write .env ─────────────────────────────────────────────────────

write_env() {
    log "Writing .env..."

    # Generate ClickHouse admin hash for Caddy basic auth
    local ch_admin_hash
    ch_admin_hash=$(docker run --rm caddy:2.9-alpine caddy hash-password --plaintext "${CLICKHOUSE_PASSWORD}" 2>/dev/null || echo "GENERATE_ME")

    # Generate Studio password hash for Caddy basic auth
    local studio_hash
    studio_hash=$(docker run --rm caddy:2.9-alpine caddy hash-password --plaintext "${DASHBOARD_PASSWORD}" 2>/dev/null || echo "GENERATE_ME")

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
SMTP_HOST=${SMTP_HOST:-}
SMTP_PORT=${SMTP_PORT}
SMTP_USER=${SMTP_USER}
SMTP_PASS=${SMTP_PASS}
SMTP_ADMIN_EMAIL=${SMTP_ADMIN_EMAIL}
SMTP_SENDER_NAME=Orchestra MCP

# ─── Supabase Realtime ───────────────────────────────────────────
REALTIME_DB_ENC_KEY=${REALTIME_DB_ENC_KEY}
REALTIME_SECRET_KEY_BASE=${REALTIME_SECRET_KEY_BASE}

# ─── Cloudflare ──────────────────────────────────────────────────
CF_API_TOKEN=${CF_API_TOKEN:-}

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

# ─── Orchestra Services ─────────────────────────────────────────
# GATEWAY_IMAGE=ghcr.io/orchestra-mcp/gateway:latest
# NEXTJS_IMAGE=ghcr.io/orchestra-mcp/web:latest
ENVEOF

    chmod 600 "$INSTALL_DIR/.env"
    log ".env written (permissions: 600)."
}

# ─── Step 6: Update domain in Caddyfile ──────────────────────────────────────

update_domain() {
    if [ "$DOMAIN" != "orchestra-mcp.dev" ]; then
        log "Updating domain to ${DOMAIN} in Caddyfile and docker-compose.yml..."
        sed -i "s/orchestra-mcp\.dev/${DOMAIN}/g" "$INSTALL_DIR/Caddyfile"
        sed -i "s/orchestra-mcp\.dev/${DOMAIN}/g" "$INSTALL_DIR/docker-compose.yml"
        log "Domain updated."
    fi
}

# ─── Step 7: Deploy ─────────────────────────────────────────────────────────

deploy() {
    log "Pulling Docker images (this may take a few minutes)..."
    cd "$INSTALL_DIR"
    docker compose pull

    log "Starting services..."
    docker compose up -d

    log "Waiting for services to initialize..."
    sleep 15

    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Orchestra MCP — Deployment Complete!${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo ""
    docker compose ps
    echo ""
    log "Services:"
    log "  Frontend:  https://${DOMAIN}"
    log "  Studio:    https://db.${DOMAIN} (user: ${DASHBOARD_USERNAME})"
    log "  Auth:      https://auth.${DOMAIN}"
    log "  REST API:  https://rest.${DOMAIN}"
    log "  Realtime:  https://realtime.${DOMAIN}"
    log "  Storage:   https://storage.${DOMAIN}"
    log "  Edge:      https://edge.${DOMAIN}"
    log "  MCP:       https://mcp.${DOMAIN}"
    log "  Gateway:   https://api.${DOMAIN}"
    log "  Analytics: https://analytics.${DOMAIN}"
    echo ""
    echo -e "${BOLD}  Credentials Summary:${NC}"
    log "  Studio Login:     ${DASHBOARD_USERNAME} / ${DASHBOARD_PASSWORD}"
    log "  PostgreSQL:       postgres / ${POSTGRES_PASSWORD}"
    log "  ClickHouse:       orchestra / (see .env)"
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
        err "Usage: curl -fsSL https://raw.githubusercontent.com/orchestra-mcp/deploy/master/setup-server.sh | sudo bash"
        exit 1
    fi

    install_docker
    clone_repo
    collect_config
    generate_jwt_keys
    write_env
    update_domain
    deploy
}

main "$@"
