#!/bin/sh
# Build the humanlayer CLI (with the daemon inside) against your own servers.
# The CLI bakes in three environments: prod (default), beta (--beta) and dev (--dev).
# This script maps prod to your production and both beta and dev to your staging.
#
# Required env:
#   PROD_BASE, STAGING_BASE   hostname prefixes, e.g. "humanlayer" and "humanlayer-staging"
#   DOMAIN                    e.g. "example.com"
#   PROD_WORKOS_CLIENT_ID, STAGING_WORKOS_CLIENT_ID
# Hostnames follow selfhost/README.md: <base>, <base>-admin, <base>-api, <base>-sync.
# Args are passed to apps/cli/build.ts, e.g. --all or --target darwin-arm64.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
: "${PROD_BASE:?}" "${STAGING_BASE:?}" "${DOMAIN:?}" "${PROD_WORKOS_CLIENT_ID:?}" "${STAGING_WORKOS_CLIENT_ID:?}"
origins() { # prefix base
	export "$1_API_ORIGIN=https://$2-api.$DOMAIN" "$1_SYNC_ORIGIN=https://$2-sync.$DOMAIN" \
		"$1_CLOUD_ORIGIN=https://$2-admin.$DOMAIN" "$1_APP_ORIGIN=https://$2.$DOMAIN"
}
origins PROD "$PROD_BASE"
origins BETA "$STAGING_BASE"
origins DEV "$STAGING_BASE"
origins RIPTIDE_DAEMON "$PROD_BASE"
export BETA_WORKOS_CLIENT_ID="$STAGING_WORKOS_CLIENT_ID" DEV_WORKOS_CLIENT_ID="$STAGING_WORKOS_CLIENT_ID"
export BUILD_TYPE=prod
unset WORKOS_CLIENT_ID WORKOS_API_KEY 2>/dev/null || true
cd "$ROOT/apps/cli" && bun run ./build.ts "$@"
