# Omi RSS

A cross-platform RSS reader — a web app, a browser extension, and a frozen future mobile client, around a self-hostable backend.

![License](https://img.shields.io/badge/license-MIT-blue)
![Neutron](https://img.shields.io/badge/web-Neutron-8b5cf6)
![Node](https://img.shields.io/badge/backend-Node.js-339933)
![Status](https://img.shields.io/badge/status-v0.5.0%20alpha-orange)

**Website:** <https://omirss.com>

## What is this

Omi RSS is an RSS reader built as three pieces that work together:

- **`web/`** — the product: a [Neutron](https://github.com/neutron-build/neutron) app (TypeScript + Preact) that serves the web UI, the JSON API, and (as a second process) the background worker — feed refresh crons, full-text extraction, page-feed monitoring, notifications, analytics, cleanup — from one codebase on Node.js, PostgreSQL, and Redis.
- **`extension/`** — a browser extension (Chrome/Edge/Brave + Firefox) to save articles, detect and subscribe to feeds, generate a durable feed from any page (region picker), and read in a popup or side panel. Works standalone or paired with a server.
- **`app/`** — **frozen**: the Flutter client (iOS/Android/desktop) from v0.2, kept as the starting point for a future mobile client. Not part of the shipped product; the web UI replaced the Flutter web build.

Self-hosted software, not SaaS. Run your own instance and own your data.

## Repository layout

```
omi-rss/
├── web/              Neutron app: webui + API + worker (the shipped product)
├── extension/        browser extension
├── app/              frozen Flutter client (future mobile)
├── docs/             self-hosting guide, Webroll concept
├── docker-compose.yml        local/self-host stack (web, worker, postgres, redis)
├── docker-compose.prod.yml   production variant (secrets required, no defaults)
├── compose.dev.yml            dev databases only (postgres on 5433, redis on 6380)
└── PLAN.md           scope, phase history, current state
```

## Development

### Web (UI + API + worker)

Start the dev databases (PostgreSQL 16 on `localhost:5433`, Redis 7 on `localhost:6380`):

```bash
podman compose -f compose.dev.yml up -d     # or: docker compose -f compose.dev.yml up -d
```

Then:

```bash
cd web
pnpm install
cp .env.example .env        # defaults already point at compose.dev.yml (5433/6380)
pnpm db:migrate             # apply schema
pnpm dev                    # UI + API dev server
pnpm worker                 # background worker (separate terminal)
pnpm test                   # unit tests
```

Health check: `GET /health`, readiness: `GET /ready`.

### Extension

Load `extension/` as an unpacked extension:

1. Open `chrome://extensions` (or `brave://extensions`).
2. Enable **Developer mode**.
3. Click **Load unpacked** and select the `extension/` folder.

Point the extension at your server in its settings (server URL), or run it standalone.

### App (frozen)

```bash
cd app
flutter pub get
flutter run
flutter test
```

See `app/README.md` — the Flutter client is frozen, not dead.

## Self-hosting

Requirements: Docker (or Podman) + Compose.

```bash
git clone <this repo> && cd omi-rss/app
JWT_SECRET=$(openssl rand -hex 32) POSTGRES_PASSWORD=$(openssl rand -hex 16) \
  docker compose -f docker-compose.prod.yml up -d
```

The stack is four services: `web` (UI + API, port 8080 by default), `worker` (same image, background crons), `postgres:16`, `redis:7`. No nginx — the Neutron server serves statics itself; terminate TLS at your edge. Register the first user via `POST /api/auth/register`.

For a localhost stack with dev-friendly defaults, use `docker-compose.yml` instead; for databases only (local development on `web/`), use `compose.dev.yml`.

Extension: load unpacked, or build store-ready zips with `cd extension && ./build.sh`.

See [docs/self-hosting.md](docs/self-hosting.md) for the full guide.

## Environment variables

The server and worker read these from the environment (`web/.env.example` carries the same set with defaults):

| Variable | What it does |
| --- | --- |
| `DATABASE_URL` | PostgreSQL connection string (`postgres://user:pass@host:5432/db`) |
| `REDIS_URL` | Redis connection string for queue/cache (`redis://host:6379`) |
| `JWT_SECRET` | HMAC secret for auth tokens — required, no default in production |
| `PORT` | HTTP port for the UI + API server (default `3000`) |
| `JWT_EXPIRES_IN` | Access-token expiry, `jwt.sign` `expiresIn` format (default `7d`) |
| `BCRYPT_ROUNDS` | bcrypt cost factor for password hashing (default `10`) |
| `MAX_FILE_SIZE` | Max upload size in bytes — avatars, OPML import (default `5242880`, 5 MB) |
| `UPLOAD_DIR` | Directory for avatars/uploads, served from `/uploads` (default `./uploads`) |
| `ARTICLE_RETENTION_DAYS` | Days before the cleanup job deletes articles (default `90`) |
| `FRONTEND_URL` | Public origin used in verification/reset email links |
| `TRUSTED_PROXY` | Trust forwarding headers for rate limiting: `false` (direct), `true` (one proxy), or a CIDR list |
| `ALLOW_PRIVATE_FEED_URLS` | Dev-only bypass of the SSRF guard for loopback/private feed URLs (default `false`) |
| `NODE_ENV` | `development` or `production`; production enables strict auth/rate-limit behavior |

Compose additionally supports `WEB_PORT` (host port for `web`, default `8080`), `POSTGRES_PASSWORD`, and `SMTP_*`/`RATE_LIMIT_*` (see [docs/self-hosting.md](docs/self-hosting.md)).

## Status

v0.5.0 — reader core, full-stack Neutron app, full-text extraction, page feeds, bring-your-own-subscription headers, archive fallback, one visual identity across webui/popup/sidepanel. Landed: `web/` replaces the Express server and the Flutter web UI; the extension contract is preserved and re-verified end to end; the Flutter app is frozen as the future mobile client. See [PLAN.md](PLAN.md) for phase history and what is deliberately out of scope. The marketing site is live at <https://omirss.com> (its source lives in a separate private repository).

## License

MIT — see [LICENSE](LICENSE).
