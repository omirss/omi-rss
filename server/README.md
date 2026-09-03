# Omi RSS Server

Self-hostable Node + TypeScript backend for Omi RSS: fetches, stores, and
serves feeds and articles. Express + PostgreSQL (Drizzle ORM) + Redis (Bull
queues) + Socket.IO.

## Status

Alpha — being repaired to first boot. The scope is the reader core: auth,
feeds, articles, folders, stats, OPML import/export. See the repository
PLAN.md for the current phase and known gaps.

## Run (development)

```bash
cp .env.example .env          # fill in DB + JWT settings
docker compose up -d          # postgres, redis, server, migrate
```

Or without Docker:

```bash
npm install
npm run db:push               # apply schema to your Postgres
npm run dev
```

Health check: `GET http://localhost:3000/health`

## Production

```bash
cp .env.production.example .env   # fill in secrets
docker compose -f docker-compose.prod.yml up -d
```

Includes nginx, daily Postgres backups, and Prometheus/Grafana monitoring.

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

## API surface (v0.2 target)

All routes under `/api`, JWT-authenticated except auth and health.

- `POST /api/auth/register | login | refresh | logout`
- `GET/PUT /api/users/me`
- `GET/POST /api/feeds`, `GET/PUT/DELETE /api/feeds/:id`, `POST /api/feeds/:id/refresh`
- `GET /api/articles`, `GET /api/articles/:id`, `PUT /api/articles/:id/state`
- `GET/POST /api/folders`, `GET/PUT/DELETE /api/folders/:id`
- `GET /api/stats/overview | history | reading-time | tags`
- `POST /api/discovery/import/opml`, `GET /api/discovery/export/opml`
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
minutes (honoring per-feed intervals), cleanup daily, analytics hourly.

## License

MIT — see repository LICENSE.
