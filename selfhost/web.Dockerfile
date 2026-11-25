# syntax=docker/dockerfile:1.20
# Builds one of the web apps and serves it as a static single-page app.
# Build context: monorepo root.
#
# Railway passes service variables as build args, so set these on the service:
#   APP                 riptide-ui (main app) or riptide-cloud (admin app)
#   VITE_PUBLIC_*       origins, WorkOS client ID, etc. (see selfhost/README.md)
FROM oven/bun:1.3 AS build
WORKDIR /usr/src/app
ARG APP
ARG VITE_PUBLIC_RIPTIDE_API_ORIGIN
ARG VITE_PUBLIC_SYNC_ORIGIN
ARG VITE_PUBLIC_APP_ORIGIN
ARG VITE_PUBLIC_CLOUD_ORIGIN
ARG VITE_PUBLIC_WORKOS_CLIENT_ID
ARG VITE_PUBLIC_DEEP_LINK_SCHEME=selfhost-humanlayer
ARG VITE_PUBLIC_BILLING_ENFORCEMENT_ENABLED=false
ARG VITE_PUBLIC_BUILD_TYPE=prod
ARG VITE_PUBLIC_REMOTE_DAEMON_BUILD_TYPE=prod
ARG VITE_PUBLIC_ENVIRONMENT=prod
ARG RAILWAY_GIT_COMMIT_SHA=unknown
RUN test -n "$APP" && test -n "$VITE_PUBLIC_RIPTIDE_API_ORIGIN" && test -n "$VITE_PUBLIC_SYNC_ORIGIN" && test -n "$VITE_PUBLIC_WORKOS_CLIENT_ID" \
	|| (echo "Set APP, VITE_PUBLIC_RIPTIDE_API_ORIGIN, VITE_PUBLIC_SYNC_ORIGIN and VITE_PUBLIC_WORKOS_CLIENT_ID" && exit 1)
COPY package.json bun.lock bunfig.toml tsconfig.json ./
COPY --parents apps/*/package.json packages/*/package.json contracts/*/package.json vendor/*/package.json ./
RUN bun install --frozen-lockfile --filter "@humanlayer/${APP}"
COPY --parents apps/${APP} packages contracts vendor ./
RUN cd "apps/${APP}" \
	&& NODE_ENV=production NODE_OPTIONS=--max-old-space-size=6144 \
	VITE_PUBLIC_BUILD_VERSION="$(echo "$RAILWAY_GIT_COMMIT_SHA" | cut -c1-8)" \
	bunx vite build \
	&& mv dist /dist

FROM caddy:2-alpine
COPY selfhost/web.Caddyfile /etc/caddy/Caddyfile
COPY --from=build /dist /srv
