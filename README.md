# Omi RSS

A cross-platform RSS reader — a Flutter client, a browser extension, and a self-hostable backend.

![License](https://img.shields.io/badge/license-MIT-blue)
![Flutter](https://img.shields.io/badge/client-Flutter-02569B)
![Node](https://img.shields.io/badge/backend-Node.js-339933)
![Status](https://img.shields.io/badge/status-v0.2.0%20alpha-orange)

**Website:** <https://omirss.com>

## What is this

Omi RSS is an RSS reader built as three pieces that work together:

- **`app/`** — the reader client, a Flutter app (project `rss_glassmorphism_reader`). Local-first: subscriptions and articles live in on-device storage; the server is optional and syncs when configured.
- **`extension/`** — a browser extension (Chrome/Edge/Brave + Firefox) to save articles, detect and subscribe to feeds, and read in a popup or side panel. Works standalone or paired with a server.
- **`server/`** — a self-hostable Node + TypeScript backend that fetches, stores, and serves feeds and articles.

Self-hosted software, not SaaS. Run your own instance and own your data.

## Repository layout

```
omi-rss/
├── app/         Flutter reader client
├── extension/   browser extension
├── server/      backend (Node + TypeScript, docker-compose)
├── docs/        self-hosting guide, Webroll concept
├── build-web.sh builds the Flutter web UI into server/web-ui
└── PLAN.md      scope, phase history, current state
```

## Development

### Server

With Docker (builds and runs the server alongside postgres and redis; the API is at `http://localhost:3998`):

```bash
cd server
cp .env.example .env           # defaults work as-is for local dev
docker compose up --build
```

Or natively (postgres and redis in containers, server on your machine at `http://localhost:3000`):

```bash
cd server
docker run -d --name omi_pg -e POSTGRES_USER=omi_rss -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=omi_rss_db -p 5432:5432 postgres:16-alpine
docker run -d --name omi_redis -p 6379:6379 redis:7-alpine
cp .env.example .env
npm install
npm run db:push
npm run dev
```

Health check: `GET /health`.

### App

```bash
cd app
flutter pub get
flutter run                  # or: flutter run -d chrome
flutter test
```

### Extension

Load `extension/` as an unpacked extension:

1. Open `chrome://extensions` (or `brave://extensions`).
2. Enable **Developer mode**.
3. Click **Load unpacked** and select the `extension/` folder.

Point the extension at your dev server in its settings (server URL), or run it standalone.

## Self-hosting

Requirements: Docker + Docker Compose.

```bash
git clone <this repo> && cd omi-rss/app/server
cp .env.production.example .env    # set JWT_SECRET, POSTGRES_PASSWORD, REDIS_PASSWORD, CORS_ORIGIN
docker compose -f docker-compose.prod.yml up -d
```

The production stack is nginx + server + postgres + redis. The bundled nginx is HTTP-only — terminate TLS at your edge (Caddy, Traefik, nginx, Teploy, or similar). Register the first user via `POST /api/auth/register`.

Optional web UI: run `./build-web.sh` from the repo root, then `docker compose -f docker-compose.prod.yml up -d` — nginx serves the Flutter web build at `/` (absent build = API-only).

Extension: load unpacked, or build store-ready zips with `cd extension && ./build.sh`.

See [docs/self-hosting.md](docs/self-hosting.md) for the full guide.

## Status

v0.2.0 alpha — the reader core works end to end (subscribe, fetch, read, OPML, sync) and has been verified live against all three clients. See [PLAN.md](PLAN.md) for phase history and what is deliberately out of scope. The marketing site is live at <https://omirss.com> (its source lives in a separate private repository).

## License

MIT — see [LICENSE](LICENSE).
