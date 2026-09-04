# Self-Hosting Omi RSS

Guide to running your own Omi RSS server (v0.2.0). The server is a small
Docker Compose stack: nginx, the API server, PostgreSQL, and Redis.

## Requirements

- A Linux host (or any Docker-capable machine) with:
  - Docker Engine and Docker Compose v2
  - Ports 80 (or whatever you expose) reachable from your users
  - ~1 GB RAM is plenty for a personal instance

## Setup

```bash
git clone <repository> omi-rss
cd omi-rss/app/server
cp .env.production.example .env
```

Edit `.env` at minimum:

- `JWT_SECRET` — long random string. Generate one with, for example:
  `openssl rand -base64 48`
- `POSTGRES_PASSWORD`, `REDIS_PASSWORD` — secure passwords (used by the
  containers; `DATABASE_URL` and `REDIS_URL` are derived from them)
- `CORS_ORIGIN` — the origins your clients will use, comma-separated (for
  example your web UI origin and the extension `chrome-extension://...` IDs,
  if needed)

Optional: SMTP settings enable email verification and password reset; OAuth
provider keys enable the corresponding callbacks. Both are off unless
configured.

## Start

```bash
docker compose -f docker-compose.prod.yml up -d
```

Verify: `curl http://localhost/health` returns 200. The API is served under
`/api`.

## First user

Registration is open by default. Create your account:

```bash
curl -X POST http://localhost/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","username":"you","password":"a-long-password"}'
```

Then point your clients at the server:

- **Extension** — open the popup, go to settings, set the server URL, log in.
- **App** — Settings, set the server URL, log in. On the web build served
  from this server (below), the default is its own origin.

## Optional web UI

The Flutter app builds to a web bundle that nginx serves at `/` when present:

```bash
# from the repository root (requires the Flutter SDK)
./build-web.sh
cd server && docker compose -f docker-compose.prod.yml up -d
```

If `server/web-ui/` is absent or empty, the stack is API-only and non-API
paths return 404 — nothing breaks.

## TLS

The bundled nginx listens on plain HTTP (port 80) by design. Terminate TLS at
an edge proxy in front of it — Caddy, Traefik, plain nginx, Teploy, or your
hosting provider's load balancer — and forward to port 80. Set
`CORS_ORIGIN` to your HTTPS origins. Do not expose the Postgres or Redis
containers directly; the compose file already publishes no database ports.

## Backups

Everything that matters is in Postgres. A daily dump is enough:

```bash
docker exec omi_rss_postgres pg_dump -U omi_user omi_rss > omi-rss-$(date +%F).sql
```

(The container name, user, and database come from your `.env`.) Store the
dumps off-host. Redis holds only queue state and is rebuildable; the Postgres
volume (`postgres_data`) is the one to protect.

## Upgrading

```bash
git pull
cd server
docker compose -f docker-compose.prod.yml build
docker compose -f docker-compose.prod.yml up -d
```

Schema changes are applied by the server on boot. Data volumes persist across
rebuilds. If you use the web UI, re-run `./build-web.sh` after upgrades that
change the app.
