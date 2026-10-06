# Read/Star Sync Protocol (design record)

Status: design for unfreeze time. The Flutter client is a frozen reference
client; nothing here is implemented. No full two-way sync is to be built
before the unfreeze decision.

## Current server capability (researched 2026-10-04)

DB table `user_article_states` (web/src/data/db/schema.ts) already stores
per-(userId, articleId) state with timestamps — PK is (userId, articleId):

- `isRead`, `isStarred` (bool, default false)
- `readAt` (nullable timestamp) — set to now() on transition to read,
  preserved (COALESCE) on repeated read, cleared to NULL on un-read
- `starredAt` (nullable timestamp) — same semantics for star
- `updatedAt` (timestamp, defaultNow) — rewritten on every state write

Written by three API routes plus the GReader router, all with the same
semantics (state.tsx, batch-update.tsx, mark-all-read.tsx,
lib/greader/router.server.ts): flag-clear nulls the flag timestamp and
bumps `updatedAt`; repeated true keeps the original event time.

What the JSON payloads actually expose to clients:

- `GET /api/articles` (list — the route the Flutter client syncs against):
  `isRead`, `isStarred`, `readAt`. **No `starredAt`, no `updatedAt`.**
- `GET /api/articles/:id`: same set.
- Update 2026-10-06 (round-4 audit fixes): both routes additionally
  expose `guid` (the publisher GUID from `articles.guid`), so clients
  key identity on `(feedId, guid)` instead of substituting the URL.
- `PATCH /api/articles/:id/state`, `POST /api/articles/batch-update`,
  `POST /api/articles/mark-all-read`: return `{message}` / `{message,
  updatedCount}` only — no state echo, no timestamps.

Web client (`lib/api-types.ts` `ArticleListItem`): types `readAt` only;
the web UI does not render it (it is consumed by analytics/worker queries).

Flutter client current behavior (for context):

- `Article.fromJson` ignores the server `readAt`; local `updatedAt`
  defaults to parse-time `DateTime.now()`. The model's `readAt`/`starredAt`
  getters are approximations off that local `updatedAt`.
- Sync pull (`sync_provider.dart` → `articleDao.upsertServerArticles`,
  as of the round-4 fixes) reconciles identities: a local row with the
  same `(feedId, guid)` but a different id is rekeyed to the server id
  and local read/star state survives that one-time merge. Repeat pulls
  are full-row upserts of server-owned columns, so a local flag change
  is still overwritten by the next pull — durable two-way state sync
  remains the design below, not current behavior.
- Subscription push is provenance-gated (`LibraryOwner` in
  `sync_provider.dart`): only feed URLs the active account created
  locally (pending creates) are uploaded; legacy/unassigned libraries
  and other accounts' pulled rows never push.
- Push (`article_actions_provider.dart`) is fire-and-forget best-effort
  `updateArticleState`; failures are dropped, and the next pull clobbers
  the local state that failed to push.

## Server delta needed

Everything needed already exists in the DB; only the payload select
columns are missing. At unfreeze, additively:

1. Include `starredAt` and `updatedAt` (as `stateUpdatedAt`) from the
   `user_article_states` join in the article list and detail select
   columns. Purely additive to the response shape.
2. Optionally have the three state-write endpoints echo the resulting
   state row (flags + timestamps) so a client can confirm its push and
   adopt the server-assigned timestamp instead of guessing.

Caveat to resolve at unfreeze: `updatedAt` is one column for both flags.
A read-write bumps it, which makes an untouched stale star value look
newer. Per-flag ordering is still derivable: flag=true orders by its own
`readAt`/`starredAt`; flag=false (timestamp NULL) orders by `updatedAt`.
This works but conflates transitions that happen within the same
`updatedAt` resolution; if that ever matters, split into
`readStateUpdatedAt`/`starStateUpdatedAt`.

## Design: last-write-wins per article-state

### Client

- Local read/star carries a client-side `stateUpdatedAt` (monotonic wall
  clock, set at the moment of the local state change) and a `dirty` flag
  (set on local change, cleared on successful push).
- On sync: push all dirty states with their client timestamps
  (`updateArticleState` / batch endpoints, or a dedicated batch endpoint
  carrying per-flag timestamps if the existing bodies prove insufficient).
- Pull server article payloads; for each article apply server state only
  where the server timestamp is strictly newer than the local
  `stateUpdatedAt` AND the local state is not dirty. Never overwrite a
  dirty local state from a pull.

### Server

- Stores `stateUpdatedAt` (already `user_article_states.updatedAt`, or the
  per-flag split above) per (user, article), assigned server-side at
  write time.
- If pushes carry client timestamps, server stamps its own receive time
  rather than trusting client clocks for ordering; client timestamps are
  advisory. (Server-clock LWW avoids the multi-device clock-skew problem;
  client clocks only break ties locally.)

## Tombstones

No tombstones. Read/star are state flags, not set membership: un-read and
un-star are *newer states* with newer timestamps, not deletions, and the
LWW rule above handles them identically. Tombstones only become necessary
if user-initiated hard article deletion is ever added (deletion is
set-membership removal and cannot be represented as a newer flag value).

## Unfreeze checklist

1. Server: expose `starredAt` + `stateUpdatedAt` in list/detail payloads
   (additive select columns; DB unchanged).
2. Server: state-write endpoints echo the resulting state row.
3. Client: add `stateUpdatedAt` + dirty tracking to local state; replace
   the full-row clobber in the sync pull with the guarded merge above.
4. Client: retry dirty pushes on reconnect instead of dropping failures.
5. Tests: newer-server/dirty-local, newer-server/clean-local,
   older-server, un-read and un-star transitions (NULL timestamps).
