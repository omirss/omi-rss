# Omi RSS

A cross-platform RSS reader — a Flutter client, a browser extension, and a self-hostable backend.

![License](https://img.shields.io/badge/license-MIT-blue)
![Flutter](https://img.shields.io/badge/client-Flutter-02569B)
![Node](https://img.shields.io/badge/backend-Node.js-339933)
![Status](https://img.shields.io/badge/status-alpha-orange)

**Website:** <https://omirss.com>

## What is this

Omi RSS is an RSS reader built as three pieces that work together:

- **`app/`** — the reader client, a Flutter app (project `rss_glassmorphism_reader`).
- **`extension/`** — a browser extension to subscribe to feeds from the web.
- **`server/`** — a Node + TypeScript backend (Dockerized) that fetches, stores, and serves subscriptions and articles.

## Repository layout

```
omi-rss/
├── app/         Flutter reader client
├── extension/   browser extension
└── server/      backend (Node + TypeScript, docker-compose)
```

## Quick start

### Backend

```bash
cd server
cp .env.example .env           # fill in DB + config
docker compose up -d
```

### App

```bash
cd app
flutter pub get
flutter run
```

### Extension

Load `extension/` as an unpacked extension:

1. Open `chrome://extensions` (or `brave://extensions`).
2. Enable **Developer mode**.
3. Click **Load unpacked** and select the `extension/` folder.

## Status

Alpha — under active development. The marketing site is live at <https://omirss.com> (its source lives in a separate private repository).

## License

MIT — see [LICENSE](LICENSE).
