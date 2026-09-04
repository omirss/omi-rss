# Omi RSS Server

Self-hostable Node + TypeScript backend for Omi RSS: fetches, stores, and
serves feeds and articles. Express + PostgreSQL (Drizzle ORM) + Redis (Bull
queues) + Socket.IO.

## Status

v0.2.0 alpha — the reader core is functional and live-verified: auth, feeds,
articles, folders, stats, OPML import/export, background fetching with
User-Agent/timeout/retry. See the repository PLAN.md for phase history and
known debts.

## Run (development)

With Docker (builds the server, runs postgres + redis alongside; API at
`http://localhost:3998`; database and redis have no host ports):

```bash
cp .env.example .env           # defaults work as-is for local dev
docker compose up --build
```

Or natively (postgres and redis in containers, server at
`http://localhost:3000`):

```bash
docker run -d --name omi_pg -e POSTGRES_USER=omi_rss -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=omi_rss_db -p 5432:5432 postgres:16-alpine
docker run -d --name omi_redis -p 6379:6379 redis:7-alpine
cp .env.example .env
npm install
npm run db:push                # apply schema to your Postgres
npm run dev
```

Health check: `GET /health` (both setups).

## Production

```bash
cp .env.production.example .env    # set JWT_SECRET, DB/Redis passwords, CORS_ORIGIN
docker compose -f docker-compose.prod.yml up -d
```

The stack is nginx + server + postgres + redis, all healthchecked. The
bundled nginx is HTTP-only (`:80`) — terminate TLS at your edge proxy and
forward to it. nginx serves an optional web UI from `./web-ui` when that
directory exists (build it with `./build-web.sh` from the repo root); an
absent or empty `web-ui` means API-only. See `docs/self-hosting.md` in the
repository root for the full guide.

## Environment variables

See `.env.example` (development) and `.env.production.example` (production)
for the full list. The essentials:

- `DATABASE_URL` — Postgres connection string
- `REDIS_URL` — Redis connection string (or `REDIS_HOST` + `REDIS_PORT`)
- `JWT_SECRET` — signing key; generate a long random string for production
- `JWT_EXPIRES_IN` — access token lifetime (default `7d`)
- `CORS_ORIGIN` — allowed origins, comma-separated
- `FRONTEND_URL` — used in email links
- Optional, feature-gating: `SMTP_*` (email verify/password reset), OAuth
  provider keys

## Scripts

```bash
npm run dev          # tsx watch
npm run build        # tsc
npm run typecheck    # tsc --noEmit
npm run test         # jest
npm run db:generate  # drizzle-kit generate migrations
npm run db:push      # push schema directly
npm run db:migrate   # run migrations
npm run db:seed      # seed sample data
```

## API surface (v0.2)

All routes under `/api`, JWT-authenticated except auth and health.

- `POST /api/auth/register | login | refresh | logout` — login/register return
  an access token and a refresh token; `refresh` rotates the pair. Email
  verification and password reset routes exist and activate when SMTP is
  configured.
- `GET/PUT /api/users/me`
- `GET/POST /api/feeds`, `GET/PUT/DELETE /api/feeds/:id`, `POST /api/feeds/:id/refresh`
- `GET /api/articles` (filters + `?search=`), `GET /api/articles/:id`,
  `PUT /api/articles/:id/state`
- `GET/POST /api/folders`, `GET/PUT/DELETE /api/folders/:id`
- `GET /api/stats/overview | history | reading-time | tags`
- `POST /api/discovery/import/opml`, `GET /api/discovery/export/opml`
  (export uses folder names)
- `GET /api/analytics/...` (reading analytics)
- `GET /health`

## Architecture

```
src/
  server.ts            Express bootstrap, route mounting
  database/            Drizzle schema, migrations, seed
  middleware/          authentication, error handling, rate limiting
  routes/              one router per resource
  services/            discovery (OPML), analytics, redis, socket, email
  workers/             Bull queues: feed updates (5-min cron), cleanup, analytics
```

Background work runs through Bull queues on Redis: feeds refresh every 5
minutes (honoring per-feed intervals) with User-Agent, timeout, and retry on
fetches; cleanup daily; analytics hourly.

## License

MIT — see repository LICENSE.
