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
NC='\033[0m'

log() { echo -e "${GREEN}[deploy]${NC} $*"; }
warn() { echo -e "${YELLOW}[deploy]${NC} $*"; }
err() { echo -e "${RED}[deploy]${NC} $*" >&2; }

# Check prerequisites
command -v docker >/dev/null 2>&1 || { err "docker is required but not installed."; exit 1; }
docker compose version >/dev/null 2>&1 || { err "docker compose v2 is required."; exit 1; }

# Check .env exists
if [ ! -f .env ]; then
    err ".env file not found. Run: cp .env.example .env"
    err "Then fill in all required secrets."
    exit 1
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
