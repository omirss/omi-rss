# Omi RSS Web

The shipped product: one Neutron app serving the web UI, the JSON API, and the background worker. TypeScript everywhere — Preact for the UI (SSR + islands), Drizzle over PostgreSQL, BullMQ over Redis.

## Development

```bash
pnpm install
cp .env.example .env    # defaults point at compose.dev.yml (see below)
pnpm db:migrate         # apply drizzle migrations
pnpm dev                # dev server (UI + API)
pnpm worker             # background worker — separate terminal
pnpm check              # tsc --noEmit
pnpm test               # vitest
```

Databases: from the repo root, `podman compose -f compose.dev.yml up -d`
(or the `docker compose` equivalent) starts PostgreSQL 16 on `localhost:5433`
and Redis 7 on `localhost:6380` — exactly what `.env.example` defaults to.

The worker registers the crons (feed refresh every 5 min, full-text extraction on a dedicated queue, page-feed monitoring with conditional GET, analytics hourly, cleanup nightly) and consumes the same queues the API enqueues into. Per-feed HTTP headers (bring-your-own-subscription cookies) ride along on feed, extraction, and page fetches — same-origin only.

## Production

```bash
pnpm build:docker       # -> dist/server.mjs (+ SSR runtime, client assets)
PORT=3000 node dist/server.mjs       # UI + API
pnpm worker                          # worker, separate process
```

Environment (full set, matching `.env.example`):

- `DATABASE_URL` — PostgreSQL connection string
- `REDIS_URL` — Redis connection string (queue/cache)
- `JWT_SECRET` — HMAC secret for auth tokens; required in production
- `PORT` — HTTP port for the UI + API server (default `3000`)
- `JWT_EXPIRES_IN` — access-token expiry, `jwt.sign` format (default `7d`)
- `BCRYPT_ROUNDS` — bcrypt cost factor for password hashing (default `10`)
- `MAX_FILE_SIZE` — max upload size in bytes: avatars, OPML import (default 5 MB)
- `UPLOAD_DIR` — directory for avatars/uploads, served from `/uploads` (default `./uploads`)
- `ARTICLE_RETENTION_DAYS` — days before the cleanup job deletes articles (default `90`)
- `FRONTEND_URL` — public origin used in verification/reset email links
- `TRUSTED_PROXY` — trust forwarding headers for rate limiting: `false`, `true`, or a CIDR list
- `ALLOW_PRIVATE_FEED_URLS` — dev-only SSRF-guard bypass for private feed URLs (default `false`)
- `NODE_ENV` — `development`/`production`; production enables strict auth/rate-limit behavior

The server needs all of the above at boot (most have defaults); the worker needs `DATABASE_URL` + `REDIS_URL`; crons live only in the worker process. Optional: `SMTP_*` for email delivery, `RATE_LIMIT_*` for API limits.

The worker is not bundled to `dist` — `neutron-ts worker` runs `src/worker.ts` (see `neutron.config.ts`) through Vite's SSR transform, so production needs `src/` + `node_modules` + `neutron.config.ts` present. The Docker image ships exactly that.

## Docker

`Dockerfile` (build context: `web/`) is multi-stage: install + `build:docker` in a builder, then a non-root `node:22-alpine` runtime with `dist/`, `node_modules/`, `src/`, and `drizzle/`. The repo-root compose files run it as two services from the one image:

```bash
# from the repo root
docker compose up -d --build      # web + worker + postgres + redis
```

Migrations apply automatically in the `web` service command before the server starts.
