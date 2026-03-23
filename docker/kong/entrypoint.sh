#!/bin/bash
# Kong entrypoint that substitutes env vars in kong.yml template.
# Kong's declarative config does NOT support ${ENV_VAR} interpolation,
# so we must pre-process the template before starting Kong.

set -e

TEMPLATE="/var/lib/kong/kong.yml.template"
OUTPUT="/tmp/kong.yml"
export KONG_DECLARATIVE_CONFIG="$OUTPUT"

if [ ! -f "$TEMPLATE" ]; then
    echo "ERROR: Kong config template not found at $TEMPLATE"
    exit 1
fi

# Replace ${ANON_KEY} and ${SERVICE_ROLE_KEY} with actual env var values
sed \
    -e "s|\${ANON_KEY}|${ANON_KEY}|g" \
    -e "s|\${SERVICE_ROLE_KEY}|${SERVICE_ROLE_KEY}|g" \
    "$TEMPLATE" > "$OUTPUT"

echo "Kong config generated from template (keys substituted)"

# Hand off to the official Kong entrypoint
exec /entrypoint.sh kong docker-start
