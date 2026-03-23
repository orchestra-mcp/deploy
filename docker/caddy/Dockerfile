# =============================================================================
# Caddy with Cloudflare DNS Plugin
#
# Builds Caddy from source with the cloudflare DNS module for DNS-01 ACME
# challenges, required for wildcard TLS certificates behind Cloudflare proxy.
#
# Usage (standalone):
#   docker build -t orchestra-caddy ./docker/caddy
#
# In docker-compose, this is built automatically via:
#   caddy:
#     build:
#       context: ./docker/caddy
#       dockerfile: Dockerfile
# =============================================================================

# ── Build stage: compile Caddy with cloudflare DNS plugin ────────────────────

FROM caddy:2.9-builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

# ── Runtime stage: minimal Caddy image with custom binary ────────────────────

FROM caddy:2.9-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Create log directory for Caddyfile log outputs
RUN mkdir -p /var/log/caddy

EXPOSE 80 443 443/udp
