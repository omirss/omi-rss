# omi-rss — Plan

Single source of truth for scope, state, and build order. When this file and
anything else disagree, this file wins.

## What this is

A cross-platform RSS reader built as three pieces that work together:

- **`web/`** — the product: a Neutron app (TypeScript + Preact) serving the
  web UI, the JSON API, and — as a second process from the same image — the
  background worker. PostgreSQL via Drizzle, Redis via BullMQ, multi-user
  JWT auth.
- **`extension/`** — browser extension (Chrome/Edge/Brave + Firefox): save
  articles, detect and subscribe to feeds, read in popup or side panel.
- **`app/`** — frozen: the v0.2 Flutter client, kept as the starting point
  for a future iOS/Android client against the same API.

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

## Current state (v0.5.0)

Shipped and deployed: reader core, full-stack Neutron app (web/),
full-text extraction, page feeds, bring-your-own-subscription headers,
archive fallback, one visual identity across webui/popup/sidepanel,
deployed to infra-home via teploy. Remaining: store submissions, Docker
registry publish (owner decisions); greader API evaluation stays v1.x.

## v0.5.0 — Extraction UX, BYO subscriptions, parity (2026-09-05)

- Full-text at subscribe time (default on) + reader badges + per-feed
  extraction health indicators
- Per-feed HTTP headers (cookies) — allowlisted, host-scoped on
  redirects AND article links, never logged; migration 0004
- Archive fallback (archive.org / archive.today) in all three readers
- Extension parity pass: light mode, one chip/dot/toast language,
  error states with retry, pop-out opens the full web app
- Page transitions, confirm-password, drawer/spacing polish waves
- Security hardening from the release audit: password change revokes
  tokens; control-char header rejection; stats index (0005)

## v0.4.0 — Extraction and page feeds (2026-09-05)

## v0.3.0 — Full-stack Neutron migration (2026-09-04/05)

**Decision.** `web/` — one Neutron app — replaces both the Express server
and the Flutter web UI. The Flutter client is frozen as the future mobile
client.

**Why.**
- Flutter web tax: the webui shipped as a multi-MB WASM/JS bundle behind
  nginx, built by a shell script outside any server lifecycle; SSR, islands,
  and sane asset story were out of reach.
- TS-everywhere: two languages (Dart client, TS server) for one product;
  contract parity was maintained by hand.
- Neutron showcase: omi-rss is a real product; running it on Neutron exercises
  the framework's SSR, API-routes, worker, and docker-preset paths in
  production shape.

**What.**
- `web/` serves webui + API from one Node process (`dist/server.mjs` from
  `pnpm build:docker`) and the worker runs as a second process from the same
  image (feed/notifications/analytics/cleanup crons via BullMQ).
- API contracts ported byte-compatible with v0.2.1 (auth shape, error JSON,
  rate-limit points/windows, OPML, PUT /articles/:id/state).
- Extension contract preserved and re-verified end to end against the new
  server (login, Find Feeds subscribe + toast, server-side read sync, JSON
  backup, OPML round-trip, sidepanel local state) — extension code untouched.
- Compose rewritten at the repo root: web + worker + postgres:16 + redis:7,
  healthchecks, no nginx (Neutron serves statics; TLS stays at the edge),
  host port 8080 default.
- Found and fixed in web/ during verification: theme popover unclickable
  (backdrop-filter stacking contexts trapped its z-index below content).

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

Flattened repo layout (Flutter app, extension, and the since-retired Express
backend as top-level dirs), Webroll
adopted as `docs/webroll/`, empty `_archive/` deleted, extension reduced to
the canonical file set (one manifest per target, one popup, one sidepanel),
server scope cut (137 routes to ~50, 25 tables to 9, dependencies halved),
Dart/Serverpod leftovers removed, READMEs rewritten to match reality.

### Phase 1 — Server boots (VERIFIED)

- DONE: middleware (validation/asyncHandler/auth), workers (cleanup/analytics),
  aiService removal, ~150 type errors fixed, fresh drizzle baseline, jest
  consolidated, 11/11 unit tests
- VERIFIED 2026-09 (podman postgres:16 + redis:7, native tsx): boot clean,
  /health 200, register/login/subscribe/refresh/articles all pass via curl
  against a real feed. Fixed during boot: dotenv import-hoisting bug
  (`import 'dotenv/config'` now first in server.ts — eager rateLimiter Redis
  clients were reading env before it loaded)
- Phase 4 hardening DONE 2026-09: refresh/logout endpoints (rotating
  refresh), UA/timeout/retry on rss-parser, compose dev builds+starts with
  healthchecks (no host DB ports), Redis env unified, rateLimiter init
  graceful

### Phase 2 — Extension goes real (VERIFIED)

- DONE: config unified in js/config.js (`settings.apiUrl`, `access_token`),
  background service-worker crash fixed (no undeclared globals, no dead
  WebSocket loop), endpoints mapped to real API (OPML via discovery, state
  via PUT /articles/:id), MV3 fixes (DOMParser fallback, scripting/downloads
  permissions, Firefox classic background), sidepanel crash fixed
- VERIFIED 2026-09-04 against the running server (live checklist 4/4):
  load unpacked clean, settings + login, Find Feeds → subscribe → row in
  POST /api/feeds, article state sync, OPML import/export, JSON backup,
  offline fallback. The harness found and fixed 5 bugs on the way (parser,
  Find Feeds, sidepanel, OPML UI, server-URL settings field).

### Phase 3 — App connects and shrinks (VERIFIED)

- DONE: 218 → 106 dart files (scope Gone list removed), runtime server URL
  setting (SharedPreferences key `serverUrl`, ApiConfig.setServerUrl),
  web/ re-scaffolded (sql.js loader for drift-on-web), 23 deps dropped,
  webfeed replaced with direct package:xml parsing
- VERIFIED 2026-09: `flutter analyze` 0 errors (was 531),
  `flutter build web --no-wasm-dry-run` succeeds, 19/19 widget tests pass.
  Desktop/native builds untested (wasm blocked by win32/ffi transitive deps)
- Known debts: api_feed_provider assumes integer server IDs (bridged via
  toString, reconcile in Phase 4); per-feed updateFrequency not honored in
  local refresh scheduling

### Phase 4 — v0.2 release (all done except release mechanics)

- DONE: full E2E (extension subscribe → server cron fetch → app read)
- DONE: OPML import/export verified against real data (app, extension, and
  server paths; export uses folder names)
- DONE: store-ready zips via `extension/build.sh`; real Firefox gecko id
  (`{41a6adaa-f9f6-429c-b579-48e0f0697dfe}`)
- DONE: optional web UI — a root build script compiled the Flutter web
  bundle and prod compose served it through nginx (absent = API-only);
  retired wholesale by the v0.3.0 migration
- DONE: READMEs, docs/self-hosting.md, and this plan updated to match
  shipped reality
- DONE: tagged `v0.2.0` (2026-09-04). Remaining: publish Docker image to a registry

### v0.3.0 — Full-stack Neutron migration (DONE)

- DONE: `web/` Neutron app (webui + API + worker) replaces the Express
  server and the Flutter web UI; both retired (git history preserves them)
- DONE: extension contract re-verified against the new server, extension
  code untouched
- DONE: Flutter app frozen as the future mobile client
- DONE: root compose (web/worker/postgres/redis, no nginx), web/Dockerfile,
  docs updated

### Post-v0.2 axis: aggregation parity and feed generation

The original product ambition was FreshRSS + FullTextRSS + RSSHub combined.
The reader core (FreshRSS role) is v0.2. The remaining axes, deliberately
scoped:

- **v0.4 — Full-text extraction (FullTextRSS role): first-class.** At feed
  update time, optionally fetch the article page and rewrite summary content
  via Mozilla Readability (MIT — was already a dependency), with a per-site
  selector override file (seeds exist: app `rules/extraction`, extension
  `js/extractors/site-specific.js`). Per-feed opt-in flag.
- **v1.x — Page-to-feed generation (scoped RSSHub role).** Point at any
  page, select the content region, get a durable feed — same extraction
  engine, extension gets "generate feed from this page." RSSHub itself is
  consumed, not replaced (any RSSHub URL works as a feed source); rebuilding
  its thousands of community routes means inheriting the maintenance
  treadmill without the community.
- **greader-compatible API — NOW THE MOBILE STRATEGY (decided 2026-09-05).**
  The protocol FreshRSS exposes; the de-facto standard third-party readers
  speak. Implementing it unlocks completely free, maintained mobile
  clients (NetNewsWire on iOS; FeedMe/FocusReader on Android) with zero
  first-party maintenance — replacing the frozen-Flutter-as-mobile plan.
  The Flutter app stays frozen indefinitely (reference only). FreshRSS is
  AGPL — spec reference only, never code; the protocol is documented
  publicly. Pair with a PWA manifest so the webui installs on phones
  without any client.

**License rules for the eval sprint** (clone FreshRSS, RSSHub, and study
fivefilters' approach as untracked local references):
- FreshRSS is **AGPL-3.0** — spec reference only. Never copy code into this
  MIT repo. Extract feature matrices and behavior; reimplement fresh.
- RSSHub is **MIT** — selectively portable with attribution.
- fivefilters FullTextRSS is proprietary — concept/pattern reference only;
  the MIT-licensed engine core is Mozilla Readability.

## Design decisions

1. Three pieces, one repo — tight coupling between web app, extension, and
   (frozen) mobile client.
2. Neutron + Preact for the web app (v0.3) — SSR, islands, API routes, and
   the worker in one TypeScript codebase; replaced the Flutter web UI. The
   Flutter client remains the mobile path, frozen until mobile is a priority.
3. Self-hostable, not SaaS — matches the portfolio pattern (Teploy, Tebian);
   own your data.
4. Node + TypeScript everywhere — the v0.2 Express server was ported, not
   rewritten, into Neutron API routes (byte-compatible contracts); a rewrite
   bought nothing, the runtime swap bought TS-everywhere.
5. Reader core first, network layer (Webroll) never blocks the reader —
   discovery module is the only seam.

## Non-goals (v0.2)

AI summarization/ranking, social features, market data, paywall bypass,
content generation, native push, multi-device realtime sync. All previously
attempted; see Gone above and git history.
