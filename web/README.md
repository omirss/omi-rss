# Omi RSS Web

The shipped product: one Neutron app serving the web UI, the JSON API, and the background worker. TypeScript everywhere — Preact for the UI (SSR + islands), Drizzle over PostgreSQL, BullMQ over Redis.

## Development

```bash
pnpm install
cp .env.example .env    # DATABASE_URL, REDIS_URL, JWT_SECRET (+ optional SMTP_*)
pnpm db:migrate         # apply drizzle migrations
pnpm dev                # dev server (UI + API)
pnpm worker             # background worker — separate terminal
pnpm check              # tsc --noEmit
pnpm test               # vitest
```

The worker registers the crons (feed refresh every 5 min, analytics hourly, cleanup nightly) and consumes the same queue the API enqueues into.

## Production

```bash
pnpm build:docker       # -> dist/server.mjs (+ SSR runtime, client assets)
PORT=3000 node dist/server.mjs       # UI + API
pnpm worker                          # worker, separate process
```

Env needed at boot for the server: `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `PORT` (optional: `UPLOAD_DIR`, `SMTP_*` for email, `RATE_LIMIT_*`). The worker needs `DATABASE_URL` + `REDIS_URL`; crons live only in the worker process.

The worker is not bundled to `dist` — `neutron-ts worker` runs `src/worker.ts` (see `neutron.config.ts`) through Vite's SSR transform, so production needs `src/` + `node_modules` + `neutron.config.ts` present. The Docker image ships exactly that.

## Docker

`Dockerfile` (build context: `web/`) is multi-stage: install + `build:docker` in a builder, then a non-root `node:22-alpine` runtime with `dist/`, `node_modules/`, `src/`, and `drizzle/`. The repo-root compose files run it as two services from the one image:

```bash
# from the repo root
docker compose up -d --build      # web + worker + postgres + redis
```

Migrations apply automatically in the `web` service command before the server starts.
