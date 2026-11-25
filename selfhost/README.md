# Self-hosting HumanLayer on Railway

HumanLayer's official self-host reference (`.claude/skills/self-host-humanlayer/`) targets AWS with Pulumi. This folder is what we used to run the same code on [Railway](https://railway.com) for a small team: no AWS account, no Pulumi, one Railway project.

It is a record of a working setup, not a supported installer. Nothing here is endorsed by HumanLayer.

## What works

Verified on our deployment (staging and production, upstream release 0.203.0):

- Login through WorkOS AuthKit, organization creation, and live sync in the web app
- A daemon on a developer's Mac connecting, cloning a repo, and running an agent session end to end
- Server-side titles and summaries through OpenRouter
- Deploys from GitHub on push, with a separate branch per environment
- Scheduled Postgres volume backups

Not set up or not tested here: the desktop apps, a real GitHub App (pull request status), Slack/Linear/Jira, Stripe billing, Resend onboarding email, restoring from a backup.

## What you need

- A Railway account
- A WorkOS account (required: all login goes through it)
- A domain you can add DNS records to
- Bun, to build the CLI
- Optional: an OpenRouter or Anthropic key for titles and summaries

## Files here

| File | Purpose |
|---|---|
| `api.Dockerfile`, `sync.Dockerfile` | `apps/riptide-api` and `apps/riptide-electric-proxy` without the Sentry source-map stage. Railway rejects BuildKit `--mount=type=secret`. |
| `jobs.Dockerfile`, `jobs.sh` | One container that runs database migrations on start, then the stale-daemon sweeper every minute and database maintenance once a day. Replaces three AWS Lambdas. Railway cron cannot run more often than every 5 minutes, so the sweeper loops. |
| `web.Dockerfile`, `web.Caddyfile` | Builds `riptide-ui` or `riptide-cloud` and serves it with Caddy as a single-page app. |
| `build-web.sh` | Builds the two web apps locally instead, if you prefer to upload prebuilt sites. |
| `build-cli.sh` | Builds the CLI and daemon against your own hostnames. |

Every Dockerfile uses the **monorepo root** as its build context. Point a Railway service at one with the `RAILWAY_DOCKERFILE_PATH` variable.

## Code changes in this fork

Three small behaviours, each switched on by an environment variable and off by default:

- **`OPENROUTER_API_KEY`** routes server-side inference through OpenRouter (`packages/ai/src/providers/primary-models.ts`).
- **`IS_BILLING_ENFORCEMENT_ENABLED=false`** now also skips Stripe when an organization is created. Upstream calls Stripe unconditionally, which fails without a real Stripe account.
- **`ALLOWED_EMAIL_DOMAINS`** limits who can create organizations and who can be invited.

## Hostnames

Pick a base name and a domain. We used flat names so one certificate level is enough:

| Purpose | Hostname | Service |
|---|---|---|
| Main app | `<base>.<domain>` | `app` |
| Admin app | `<base>-admin.<domain>` | `admin` |
| API | `<base>-api.<domain>` | `api` |
| Sync | `<base>-sync.<domain>` | `sync` |

Add each as a custom domain on its Railway service, then create the CNAME and `_railway-verify` TXT records Railway gives you. On Cloudflare, set the CNAMEs to DNS only.

These hostnames and the WorkOS client ID are baked into the web apps and the CLI at build time. Changing them later means rebuilding.

## Services

| Service | Source | Port | Volume | Public |
|---|---|---|---|---|
| `postgres` | image `postgres:18` | 5432 | `/var/lib/postgresql` | no |
| `Redis` | Railway Redis | 6379 | managed | no |
| `electric` | image `electricsql/electric:1.7.12` | 3000 | `/var/lib/electric` | no |
| `durable-streams` | `docker/durable-streams-server` | 4437 | `/var/lib/durable-streams` | no |
| `jobs` | `selfhost/jobs.Dockerfile` | none | none | no |
| `api` | `selfhost/api.Dockerfile` | 8700 | none | yes |
| `sync` | `selfhost/sync.Dockerfile` | 8888 | none | yes |
| `app` | `selfhost/web.Dockerfile` | 8080 | none | yes |
| `admin` | `selfhost/web.Dockerfile` | 8080 | none | yes |
| artifacts | Railway bucket | | | S3 endpoint |

Run exactly one `electric` and one `durable-streams`. A Railway service with a volume cannot have replicas, which enforces this.

## Setup, in order

### 1. Postgres

Version 18 is required (the migrations use `uuidv7()`), and Electric needs logical replication. Use the plain `postgres:18` image with a volume at `/var/lib/postgresql` and this start command:

```
docker-entrypoint.sh postgres -c wal_level=logical -c listen_addresses=* -c max_slot_wal_keep_size=10240 -c max_connections=200
```

Variables:

```
POSTGRES_DB=electric
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<random>
DATABASE_URL=postgresql://postgres:${{POSTGRES_PASSWORD}}@${{RAILWAY_PRIVATE_DOMAIN}}:5432/electric?sslmode=disable
```

Then turn on backups:

```bash
railway postgres pitr schedule set --daily --weekly --monthly --service postgres
```

These are volume snapshots. We have not yet done a test restore.

### 2. Redis

Add Railway's Redis. Plain standalone mode works.

### 3. Electric

```
DATABASE_URL=${{postgres.DATABASE_URL}}
ELECTRIC_SECRET=<random>
ELECTRIC_STORAGE_DIR=/var/lib/electric
ELECTRIC_DATABASE_USE_IPV6=true
ELECTRIC_LISTEN_ON_IPV6=true
ELECTRIC_LOG_COLORS=false
ELECTRIC_TCP_READ_TIMEOUT=120s
ELECTRIC_DB_POOL_SIZE=20
ELECTRIC_MAX_SHAPES=5000
ELECTRIC_SHAPE_SUSPEND_CONSUMER=true
PORT=3000
```

### 4. Durable streams

Deploy `docker/durable-streams-server` as the service root, with a volume at `/var/lib/durable-streams`. It builds a pinned commit of a third-party repository, so mirror that repository if you depend on this.

```
DS_SERVER__BIND_ADDRESS=[::]:4437
DS_STORAGE__MODE=file-fast
DS_STORAGE__DATA_DIR=/var/lib/durable-streams
DS_HTTP__ALLOW_WILDCARD_CORS=true
DS_LIMITS__MAX_STREAM_BYTES=104857600
DS_LIMITS__MAX_STREAM_NAME_SEGMENTS=256
RAILWAY_RUN_UID=0
PORT=4437
```

### 5. Jobs

```
DATABASE_URL=${{postgres.DATABASE_URL}}
RAILWAY_DOCKERFILE_PATH=selfhost/jobs.Dockerfile
```

It applies migrations each time it starts. Let it finish before the API starts on a new schema.

### 6. Artifacts bucket

Create a Railway bucket, then give it a CORS rule, because browsers upload to it directly:

```bash
aws s3api put-bucket-cors --endpoint-url <bucket endpoint> --bucket <bucket name> --cors-configuration '{
  "CORSRules": [{
    "AllowedOrigins": ["https://<base>.<domain>", "https://<base>-admin.<domain>"],
    "AllowedMethods": ["GET", "PUT", "HEAD"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3600
  }]
}'
```

### 7. WorkOS

Use a dedicated WorkOS environment per deployment.

- **Roles:** `admin`, `manager` and `member`. `admin` and `member` exist by default; add `manager`.
- **JWT template** (required). The sync proxy rejects any token without this claim:

  ```
  {
    "internal_org_id": {{organization.metadata.internal_org_id}}
  }
  ```

  It can be set with `PUT https://api.workos.com/user_management/jwt_template` and a body of `{"content": "<template>"}`.
- **Redirect URIs:** `https://<base>.<domain>/auth/callback`, `https://<base>.<domain>` and `https://<base>-admin.<domain>/auth/callback`.
- **CORS origins:** `https://<base>.<domain>` and `https://<base>-admin.<domain>`.
- **Sign-in methods:** a new production environment has every method off except SSO. Turn on what you want. Google in production needs your own Google OAuth client; a Google Workspace "Internal" client limits sign-in to your domain.
- **Webhook** (optional): `https://<base>-api.<domain>/webhooks/workos` for `organization_membership.*`, with its secret in `WORKOS_WEBHOOK_SECRET`.

### 8. API

```
RAILWAY_DOCKERFILE_PATH=selfhost/api.Dockerfile
NODE_ENV=production
STAGE=prod
PORT=8700
DATABASE_URL=${{postgres.DATABASE_URL}}
READ_REPLICA_DATABASE_URL=${{postgres.DATABASE_URL}}     # required; point it at the same database
KV_URL=${{Redis.REDIS_URL}}
REDIS_CLIENT_MODE=standalone
DURABLE_STREAMS_ORIGIN=http://${{durable-streams.RAILWAY_PRIVATE_DOMAIN}}:4437
IS_BILLING_ENFORCEMENT_ENABLED=false
BLOCK_NEW_ORG_CREATION=false
ONBOARDING_CAMPAIGN_ENABLED=false
RIPTIDE_API_ORIGIN=https://<base>-api.<domain>
APP_ORIGIN=https://<base>.<domain>
CLOUD_ORIGIN=https://<base>-admin.<domain>
WORKOS_CLIENT_ID=<yours>
WORKOS_API_KEY=<yours>
WORKOS_REDIRECT_URI=https://<base>.<domain>/auth/callback
S3_ARTIFACTS_BUCKET=<bucket name>
S3_ARTIFACTS_REGION=auto
S3_ARTIFACTS_ENDPOINT=<bucket endpoint>
S3_ACCESS_KEY_ID=<bucket key>
S3_SECRET_ACCESS_KEY=<bucket secret>
RIPTIDE_DAEMON_TOKEN_PRIVATE_KEY=<base64 of PKCS#8 PEM>
RIPTIDE_DAEMON_TOKEN_PUBLIC_KEY=<base64 of SPKI PEM>
```

Optional:

```
ALLOWED_EMAIL_DOMAINS=example.com               # comma-separated; unset allows everyone
OPENROUTER_API_KEY=<yours>                       # or ANTHROPIC_API_KEY
OPENROUTER_MODEL_SONNET=anthropic/claude-sonnet-5
OPENROUTER_MODEL_HAIKU=anthropic/claude-haiku-4.5
```

Daemon token keys, one pair per environment:

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out daemon-private.pem
openssl pkey -in daemon-private.pem -pubout -out daemon-public.pem
base64 < daemon-private.pem | tr -d '\n'   # RIPTIDE_DAEMON_TOKEN_PRIVATE_KEY
base64 < daemon-public.pem  | tr -d '\n'   # RIPTIDE_DAEMON_TOKEN_PUBLIC_KEY
```

The API refuses to start unless these are also set. Placeholder strings get it booting; the matching feature then does not work:

```
STRIPE_SECRET_KEY  STRIPE_WEBHOOK_SECRET
STRIPE_PRICE_STARTER  STRIPE_PRICE_PRO  STRIPE_PRICE_ENTERPRISE     # must start with price_
RESEND_API_KEY  RESEND_WEBHOOK_SECRET  RESEND_FROM_EMAIL  RESEND_PRODUCT_USERS_SEGMENT_ID
JIRA_CLIENT_ID  JIRA_CLIENT_SECRET  LINEAR_CLIENT_ID  LINEAR_CLIENT_SECRET
SLACK_CLIENT_ID  SLACK_APP_ID  SLACK_CLIENT_SECRET  SLACK_SIGNING_SECRET
GITHUB_APP_ID  GITHUB_APP_CLIENT_ID  GITHUB_APP_SLUG  GITHUB_APP_WEBHOOK_SECRET
GITHUB_APP_PRIVATE_KEY      # must be a real PKCS#8 RSA PEM, even a throwaway one
EXA_API_KEY  CONTEXT7_API_KEY
```

Leave `OPENAI_API_KEY`, `SENTRY_DSN` and `POSTHOG_API_KEY` unset. Set the health check path to `/health`.

### 9. Sync proxy

```
RAILWAY_DOCKERFILE_PATH=selfhost/sync.Dockerfile
NODE_ENV=production
PORT=8888
DATABASE_URL=${{postgres.DATABASE_URL}}
ELECTRIC_SECRET=${{electric.ELECTRIC_SECRET}}
ELECTRIC_SHAPE_URL=http://${{electric.RAILWAY_PRIVATE_DOMAIN}}:3000/v1/shape
DURABLE_STREAMS_ORIGIN=http://${{durable-streams.RAILWAY_PRIVATE_DOMAIN}}:4437
WORKOS_CLIENT_ID=${{api.WORKOS_CLIENT_ID}}
WORKOS_API_KEY=${{api.WORKOS_API_KEY}}
WORKOS_REDIRECT_URI=${{api.WORKOS_REDIRECT_URI}}
RIPTIDE_DAEMON_TOKEN_PUBLIC_KEY=${{api.RIPTIDE_DAEMON_TOKEN_PUBLIC_KEY}}
```

Health check path: `/`. With a wrong WorkOS client ID it starts but does not answer, because it keeps retrying the key lookup.

### 10. Web apps

Two services with the same Dockerfile. Railway passes service variables to the build:

```
RAILWAY_DOCKERFILE_PATH=selfhost/web.Dockerfile
APP=riptide-ui                                   # riptide-cloud for the admin app
VITE_PUBLIC_RIPTIDE_API_ORIGIN=https://<base>-api.<domain>
VITE_PUBLIC_SYNC_ORIGIN=https://<base>-sync.<domain>
VITE_PUBLIC_APP_ORIGIN=https://<base>.<domain>
VITE_PUBLIC_CLOUD_ORIGIN=https://<base>-admin.<domain>
VITE_PUBLIC_WORKOS_CLIENT_ID=<yours>
VITE_PUBLIC_DEEP_LINK_SCHEME=<your own scheme>
PORT=8080
```

### 11. CLI and daemon

The stock `humanlayer` npm package always talks to HumanLayer's servers. Build your own:

```bash
PROD_BASE=<base> STAGING_BASE=<staging base> DOMAIN=<domain> \
PROD_WORKOS_CLIENT_ID=<prod client id> STAGING_WORKOS_CLIENT_ID=<staging client id> \
selfhost/build-cli.sh --all
```

Binaries land in `apps/cli/dist`. With no staging, use the production values for both. Then, on each developer machine:

```bash
export HUMANLAYER_RIPTIDE_HOME=$HOME/.humanlayer-selfhost   # keeps this login apart from a stock install
humanlayer-darwin-arm64 login
humanlayer-darwin-arm64 daemon launch
```

Do not use the "Copy start command" button in the app; it gives the stock command.

## Deploying from GitHub

Connect `api`, `sync`, `jobs`, `app` and `admin` to your fork. We run two Railway environments in one project, each with its own database, volumes, bucket and secrets:

- `staging` follows `main`
- `production` follows a `production` branch

Promoting a change is a fast-forward of `production` to `main`. To take an upstream release: merge `upstream/main` into `main`, let staging deploy, test, then promote.

When you duplicate an environment, give the copy fresh values for `POSTGRES_PASSWORD`, the Redis password, `ELECTRIC_SECRET` and the daemon token keys, and point the API at the new environment's own bucket.

## Things that surprised us

- Railway rejects Dockerfiles with `--mount=type=secret`.
- Railway cron has a 5-minute minimum.
- Organization creation needs Stripe upstream, even with billing enforcement off.
- The API validates its own responses: a placeholder where a Stripe customer ID is expected fails with "Output validation failed".
- `READ_REPLICA_DATABASE_URL` is required even with one database.
- `GITHUB_APP_PRIVATE_KEY` must parse as a real PKCS#8 key at startup.
- A new production WorkOS environment has no sign-in methods enabled.
- The daemon clones over whatever protocol the project's repository address uses. An SSH address fails on a machine set up for HTTPS.
- The daemon writes worktrees under `~/.humanlayer` even when `HUMANLAYER_RIPTIDE_HOME` is set; only its login is isolated.
