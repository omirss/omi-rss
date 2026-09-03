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

Honest baseline: the three pieces were generated in isolation and had never
run. The 2026-09 restructure removed dead scope and debris; the Phase 1-3
code work below is done. Remaining verification is environmental, not code:
server live-boot needs Docker/Redis, extension live E2E needs the running
server, app needs a Flutter toolchain session.

- **Server** — Phase 1 complete: compiles clean (`tsc --noEmit` zero errors),
  unit tests 11/11, fresh drizzle baseline, jest tree consolidated.
  Blockers to live boot: compose dev still runs `npm run dev`; migrate
  service untested against live DB; no compose healthcheck yet.
- **Extension** — Phase 2 wiring complete: unified config (js/config.js,
  `settings.apiUrl` + `access_token` storage keys), all endpoints mapped to
  the real API, service-worker crash fixed, 14/14 files parse. Live E2E
  checklist in session history; run when server is up.
- **App** — Phase 3 surgery complete: 218 → 106 dart files, runtime server
  URL in settings (SharedPreferences, `serverUrl` key), dart:html removed,
  web/ re-scaffolded, zero dangling references by grep. Needs
  `flutter pub get && build_runner && flutter analyze` verification session
  (no Flutter toolchain on the build machine at time of surgery).

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

### Phase 1 — Server boots (code complete; live boot pending)

- DONE: middleware (validation/asyncHandler/auth), workers (cleanup/analytics),
  aiService removal, ~150 type errors fixed, .env.test recreated, jest trees
  consolidated, fresh drizzle baseline, 11/11 unit tests
- TODO when Docker is up: compose dev service runs `npm run dev` → build+start;
  add compose healthcheck; verify migrate service against live DB

### Phase 2 — Extension goes real (code complete; live test pending)

- DONE: config unified in js/config.js (`settings.apiUrl`, `access_token`),
  background service-worker crash fixed (no undeclared globals, no dead
  WebSocket loop), endpoints mapped to real API (OPML via discovery, state
  via PUT /articles/:id), MV3 fixes (DOMParser fallback, scripting/downloads
  permissions, Firefox classic background), sidepanel crash fixed
- TODO when server is up: live checklist — load unpacked, login, subscribe
  from a real blog, mark-read, OPML round-trip, offline path

### Phase 3 — App connects and shrinks (surgery complete; compile pending)

- DONE: 218 → 106 dart files (scope Gone list removed), runtime server URL
  setting (SharedPreferences key `serverUrl`, ApiConfig.setServerUrl),
  dart:html removed with the features that used it, web/ re-scaffolded,
  23 deps dropped, grep-clean for dangling references
- TODO when Flutter toolchain available: `flutter pub get`,
  `dart run build_runner build --delete-conflicting-outputs` (drift parts),
  `flutter analyze`, `flutter build web` + one desktop platform, tests

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
