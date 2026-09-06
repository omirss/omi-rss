# Self-Hosting Omi RSS

Guide to running your own Omi RSS instance (v0.5.0). The stack is four
Docker Compose services: `web` (the Neutron app serving the UI and the API),
`worker` (the same image running the background crons), PostgreSQL 16, and
Redis 7. There is no nginx — the web server serves its own static assets.

## Requirements

- A Linux host (or any Docker-capable machine) with:
  - Docker Engine (or Podman) and Compose v2
  - One free port for the web service (host port 8080 by default —
    rootless-friendly, no privileged ports needed)
  - ~1 GB RAM is plenty for a personal instance

## Setup

```bash
git clone <repository> omi-rss
cd omi-rss
```

Provide the required secrets (no defaults in the prod file):

- `JWT_SECRET` — long random string: `openssl rand -hex 32`
- `POSTGRES_PASSWORD` — secure password: `openssl rand -hex 16`

### Environment variables

The full set the server reads (matches `web/.env.example`, which carries the
defaults); compose wires the connection strings itself:

| Variable | What it does |
| --- | --- |
| `DATABASE_URL` | PostgreSQL connection string (`postgres://user:pass@host:5432/db`) |
| `REDIS_URL` | Redis connection string for queue/cache (`redis://host:6379`) |
| `JWT_SECRET` | HMAC secret for auth tokens — required, no default in production |
| `ALLOW_REGISTRATION` | `false` blocks new sign-ups once at least one user exists; an empty instance always allows the first registration. Recommended `false` in production after the owner registers (default open) |
| `PORT` | HTTP port for the UI + API server (default `3000`; compose maps host `8080` to it) |
| `JWT_EXPIRES_IN` | Access-token expiry, `jwt.sign` `expiresIn` format (default `7d`) |
| `BCRYPT_ROUNDS` | bcrypt cost factor for password hashing (default `10`) |
| `MAX_FILE_SIZE` | Max upload size in bytes — avatars, OPML import (default `5242880`, 5 MB) |
| `UPLOAD_DIR` | Directory for avatars/uploads, served from `/uploads` (default `./uploads`) |
| `ARTICLE_RETENTION_DAYS` | Days before the cleanup job deletes articles (default `90`) |
| `FRONTEND_URL` | Public origin used in verification/reset email links |
| `TRUSTED_PROXY` | Trust forwarding headers for rate limiting: `false` (direct), `true` (one proxy), or a CIDR list |
| `ALLOW_PRIVATE_FEED_URLS` | Dev-only bypass of the SSRF guard for loopback/private feed URLs (default `false`) |
| `NODE_ENV` | `development` or `production`; production enables strict auth/rate-limit behavior |

Also supported: `WEB_PORT` (host port for the `web` service, default `8080`)
and, set on the `web` service, `SMTP_HOST`/`SMTP_PORT`/`SMTP_USER`/`SMTP_PASS`/
`EMAIL_FROM` to enable email verification and password reset, plus
`RATE_LIMIT_MAX_REQUESTS` / `RATE_LIMIT_WINDOW_MS` to tune the API limits.

## Start

```bash
JWT_SECRET=$(openssl rand -hex 32) POSTGRES_PASSWORD=$(openssl rand -hex 16) \
  docker compose -f docker-compose.prod.yml up -d
```

For a localhost stack with dev-friendly defaults (including a default
`JWT_SECRET`), use `docker-compose.yml` instead — same four services. For
databases only while developing on `web/`, use `compose.dev.yml`
(`podman compose -f compose.dev.yml up -d`): PostgreSQL 16 published on
host `5433` and Redis 7 on `6380`, matching `web/.env.example`.

Verify: `curl http://localhost:8080/health` returns 200. The API is served
under `/api`; the web UI is at `/`.

What each service does:

- **web** — builds from `web/Dockerfile`, applies pending drizzle migrations,
  then serves the webui + API on port 3000 (published on host 8080).
- **worker** — the same image with the worker command: feed refresh every
  5 minutes, full-text extraction for feeds with it enabled (bounded,
  per-host-polite), page-feed monitoring with conditional GET, analytics
  hourly, cleanup nightly, notification emails when SMTP is configured.
  It starts only after `web` is healthy.

Per-feed HTTP headers (bring-your-own-subscription): edit any feed and
paste your paid-subscription cookie — the worker sends it with fetches
of that feed's origin so content you pay for downloads in full. Headers
are stored per feed in the database, never logged, and dropped on
cross-site redirects and cross-site article links.
- **postgres / redis** — with healthchecks; the databases are not published
  to host ports.

## First user

Registration is open by default. Set `ALLOW_REGISTRATION=false` to close
it — sign-ups are then rejected with 403 **only once at least one user
exists**, so a fresh instance can always register its first (bootstrap)
user. The recommended production flow: bring the stack up with
registration open (or closed — bootstrap still works), register your
account, then set `ALLOW_REGISTRATION=false` on the `web` service and
restart. Create the account:

```bash
curl -X POST http://localhost:8080/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","username":"you","password":"a-long-password"}'
```

Then point your clients at the server:

- **Extension** — open the popup, go to settings, set the server URL, log in.
- **Web UI** — you are already on it: `http://localhost:8080/`.
- **Mobile clients (greader)** — see below.

## Mobile clients (greader)

The server speaks the Google Reader ("greader") API, so maintained
third-party mobile clients sync against it with zero first-party apps.
Point any of these at `http://your-server/api/greader` with your username
and password:

- **NetNewsWire** (iOS/macOS) — add an account of type *FreshRSS* and enter
  the API base URL above.
- **FeedMe** (Android) — add an account of type *FreshRSS* (or *Inoreader*)
  and use the same base URL.
- **FocusReader** (Android) — add a *FreshRSS* account the same way.

Notes:

- Credentials go over the wire once (ClientLogin); subsequent requests use a
  long-lived token. Serve over HTTPS (terminate TLS at your edge as above)
  before using this on an untrusted network.
- Logging out of the web UI (or changing your password) revokes greader
  tokens too; clients re-authenticate automatically with stored credentials.
- Sync traffic is rate-limited per user (600 requests / 15 minutes) — far
  above what an initial full sync of a personal instance needs.

## TLS

The stack listens on plain HTTP by design. Terminate TLS at an edge proxy in
front of it — Caddy, Traefik, plain nginx, Teploy, or your hosting provider's
load balancer — and forward to the published web port. The webui, API, and
uploads all come from the same origin, so no extra routing is needed. Do not
expose the Postgres or Redis containers directly; compose publishes no
database ports.

## Backups

Everything that matters is in Postgres. A daily dump is enough:

```bash
docker exec omirss_postgres pg_dump -U omi_rss omi_rss > omi-rss-$(date +%F).sql
```

Store the dumps off-host. Redis holds only queue state and is rebuildable;
the Postgres volume (`postgres_data`) is the one to protect. Uploaded avatars
live in the `web_uploads` volume.

## Upgrading

```bash
git pull
docker compose -f docker-compose.prod.yml build
docker compose -f docker-compose.prod.yml up -d
```

Schema migrations apply automatically when the `web` service boots. Data
volumes persist across rebuilds.

v0.6.0 note: favicons are now derived from each feed's own origin
(`<origin>/favicon.ico`) instead of Google's favicon service. Existing
feeds keep their stored Google URLs until refreshed; to drop them
immediately, run this one-off SQL and let the UI fall back to origin
favicons:

```bash
docker exec omirss_postgres psql -U omi_rss omi_rss \
  -c "UPDATE feeds SET favicon = NULL WHERE favicon LIKE 'https://www.google.com/s2/favicons%'"
```
