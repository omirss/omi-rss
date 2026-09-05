# Self-Hosting Omi RSS

Guide to running your own Omi RSS instance (v0.3.0). The stack is four
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
cd omi-rss/app
```

Provide the required secrets (no defaults in the prod file):

- `JWT_SECRET` — long random string: `openssl rand -hex 32`
- `POSTGRES_PASSWORD` — secure password: `openssl rand -hex 16`

Optional environment (set on the `web` service): `SMTP_HOST`/`SMTP_PORT`/
`SMTP_USER`/`SMTP_PASS`/`EMAIL_FROM` enable email verification and password
reset; `UPLOAD_DIR` (default `./uploads`); `RATE_LIMIT_MAX_REQUESTS` /
`RATE_LIMIT_WINDOW_MS` tune the API limits. `DATABASE_URL`, `REDIS_URL`, and
`PORT` are wired by compose itself.

## Start

```bash
JWT_SECRET=$(openssl rand -hex 32) POSTGRES_PASSWORD=$(openssl rand -hex 16) \
  docker compose -f docker-compose.prod.yml up -d
```

For a localhost stack with dev-friendly defaults (including a default
`JWT_SECRET`), use `docker-compose.yml` instead — same four services.

Verify: `curl http://localhost:8080/health` returns 200. The API is served
under `/api`; the web UI is at `/`.

What each service does:

- **web** — builds from `web/Dockerfile`, applies pending drizzle migrations,
  then serves the webui + API on port 3000 (published on host 8080).
- **worker** — the same image with the worker command: feed refresh every
  5 minutes, analytics hourly, cleanup nightly, notification emails when
  SMTP is configured. It starts only after `web` is healthy.
- **postgres / redis** — with healthchecks; the databases are not published
  to host ports.

## First user

Registration is open by default. Create your account:

```bash
curl -X POST http://localhost:8080/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","username":"you","password":"a-long-password"}'
```

Then point your clients at the server:

- **Extension** — open the popup, go to settings, set the server URL, log in.
- **Web UI** — you are already on it: `http://localhost:8080/`.

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
