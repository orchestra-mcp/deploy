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

# Cloudflare now issues tokens with cfut_/cfat_ prefixes that exceed the
# upstream regex limit of 50 chars (see caddy-dns/cloudflare#125).
# Clone, patch the regex, and build with the local copy.
RUN git clone --depth 1 https://github.com/caddy-dns/cloudflare.git /tmp/cloudflare && \
    sed -i 's/{35,50}/{35,256}/' /tmp/cloudflare/cloudflare.go

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare=/tmp/cloudflare

# ── Runtime stage: minimal Caddy image with custom binary ────────────────────

FROM caddy:2.9-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Create log directory for Caddyfile log outputs
RUN mkdir -p /var/log/caddy

EXPOSE 80 443 443/udp
