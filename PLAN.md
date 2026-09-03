# omi-rss — Plan

Single source of truth for scope, state, and build order. When this file and
anything else disagree, this file wins.

## What this is

A cross-platform RSS reader built as three pieces that work together:

- **`app/`** — Flutter client (iOS, Android, desktop, web). Local-first:
  subscriptions and articles live in on-device SQLite (drift); the server is
  optional and syncs when configured.
- **`extension/`** — browser extension (Chrome/Edge/Brave + Firefox): save
  articles, detect and subscribe to feeds, read in popup or side panel.
- **`server/`** — self-hostable Node + TypeScript backend (Express, Postgres
  via Drizzle, Redis via Bull, Socket.IO). Multi-user JWT auth.

Self-hosted software, not SaaS. Users run their own instance and own their
data. The server is multi-user capable, so a hosted offering is possible
later, but nothing depends on one existing.

Website: <https://omirss.com> (source in a separate private repo).

## North Star: Webroll

`docs/webroll/CONCEPT.md` describes the long-term evolution: omi-rss is the
reader lane (day-one value); Webroll adds a public trust and discovery network
on top (registry of independent sites, owner identities, vouches, share
routing).

Architecture agreement already in place: Webroll's canonical state is public
append-only logs with a public read API, so a self-hosted omi-rss can consume
the network as data — no special coupling. The seam in this repo is the
server's discovery module: OPML is the only provider today; a Webroll
discovery provider drops in later without touching the reader core.

**Nothing in Webroll adds requirements to omi-rss v0.2.** It is referenced
here so its existence is deliberate, not forgotten.

## Current state (post-restructure)

Honest baseline: the three pieces were generated in isolation and have never
run, individually or together. The 2026-09 restructure removed dead scope and
debris; what remains is the reader core plus known repair work.

- **Server** — compiles? No. Route surface trimmed to 8 routers (~50 routes).
  Known blockers: three middleware files missing (`validation`,
  `asyncHandler`, `auth`), two workers missing (`cleanup.worker`,
  `analytics.worker`), `discovery` + `analytics` services still import the
  deleted `aiService`, `package-lock.json` stale after dependency cuts.
- **Extension** — all JS parses clean (fixed pre-existing syntax errors);
  manifests valid MV3. Known blockers: `background.js` uses undeclared
  `API_BASE`/`authToken` (crashes on install); server pairing untested.
- **App** — code untouched in restructure (cuts deferred to Phase 3, they need
  Flutter compile checks). Compiles web-only today: unconditional `dart:html`
  breaks desktop/mobile. Server URL is compile-time only.

## Scope

Kept after the cut (In):

- Auth: register, login, refresh, logout; JWT + bcrypt. Email verify/reset
  and OAuth callback routes exist and are env-gated (SMTP/providers optional).
- Users, feeds, articles, folders, reading stats
- Discovery: OPML import/export/validate
- Analytics: reading analytics (trimmed of AI dependencies in Phase 1)
- Extension: popup reader, side panel, save-article, feed detection,
  per-site extraction, offline queue, JSON backup export/import
- App: reader core screens, drift DB, OPML, settings, login

Later (recoverable from git history, do not rebuild from scratch without
checking history): multi-device sync (server routes + app service), search
indexing, notifications/web-push, OAuth enablement, redesigned popup UI,
reader-mode full tab, E2E P2P sync.

Gone (deleted 2026-09, intentionally not coming back): AI suite (server +
app dashboards), market/stock watchlists, paywall bypass (server + app
puppeteer bridge), teams, collaboration sessions/annotations, content
generation (newsletters/podcasts/social), extension Webrtc sync, icon
generator scripts, per-browser manifest variants beyond Chrome/Firefox,
stale build outputs, test HTML harnesses.

## Build phases

Each phase has a hard exit criterion. Do not start the next phase without it.

### Phase 0 — Structure and debris (DONE, 2026-09-02)

Flattened repo layout (`app/`, `extension/`, `server/` at root), Webroll
adopted as `docs/webroll/`, empty `_archive/` deleted, extension reduced to
the canonical file set (one manifest per target, one popup, one sidepanel),
server scope cut (137 routes to ~50, 25 tables to 9, dependencies halved),
Dart/Serverpod leftovers removed, READMEs rewritten to match reality.

### Phase 1 — Server boots

- `npm install` (refresh lockfile after dep cuts)
- Write `src/middleware/validation.ts`, `asyncHandler.ts`, `auth.ts`
- Write `src/workers/cleanup.worker.ts`, `analytics.worker.ts`
- Remove `aiService` imports from `services/discovery` + `services/analytics`
  (drop or trim AI-dependent endpoints; OPML and reading analytics must survive)
- Recreate `.env.test` (was removed; `tests/setup.ts` expects it)
- `npm run typecheck` and `npm run test` pass; jest trees consolidated

Exit criterion: `docker compose up` healthy; `GET /health` 200; register,
login, subscribe to a real feed, force refresh, list articles — all via curl.

### Phase 2 — Extension goes real

- Declare/load `API_BASE` + `authToken` properly in `background.js`
- Verify popup auth + subscribe path against the running server
- Side panel works local-first without a server
- Confirm content-script feed detection on real sites

Exit criterion: load unpacked in Chrome; click extension on a blog with a
feed; feed appears in server DB; article save works.

### Phase 3 — App connects and shrinks

- Runtime-configurable server URL in settings (today: compile-time only)
- App login + feed list + article read against the server
- Cut app scope to match server: remove market/portfolio/AI/paywall/
  collaboration/P2P screens and their dependencies (tflite, ml_algo, webrtc,
  nearby_connections, qr_flutter, workmanager, flutter_tts)
- Fix unconditional `dart:html` (conditional imports) to restore desktop and
  mobile builds; scaffold a proper `web/` entry (current web dir held only the
  old embedded extension, now deleted)

Exit criterion: subscribe via extension on desktop browser; article appears
in the app on another device/target; `flutter build` succeeds for web and at
least one desktop platform.

### Phase 4 — v0.2 release

- Full E2E: extension subscribe → server cron fetch → app read
- OPML import/export verified against real data (both app and server paths)
- Extension store-ready zips via `./build.sh` (replace placeholder Firefox
  gecko id with a real one)
- Serve the Flutter web build from the server as an optional web UI (mount
  into nginx / serve statically alongside the API; absent build = API-only).
  On web, the app's server-URL setting defaults to its own origin
- READMEs and this plan updated to match shipped reality
- Tag `v0.2.0`; publish Docker image; self-host deployment guide

## Design decisions

1. Three pieces, one repo — tight coupling between client, extension, server.
2. Flutter for the client — one codebase, all platforms; local-first with
   drift/SQLite, server optional.
3. Self-hostable, not SaaS — matches the portfolio pattern (Teploy, Tebian);
   own your data.
4. Node + TypeScript backend — existing implementation; a rewrite buys
   nothing at this scope.
5. Reader core first, network layer (Webroll) never blocks the reader —
   discovery module is the only seam.

## Non-goals (v0.2)

AI summarization/ranking, social features, market data, paywall bypass,
content generation, native push, multi-device realtime sync. All previously
attempted; see Gone above and git history.
