import { eq, and, sql, desc, asc, inArray, type SQL } from "drizzle-orm";
import { articles, feeds, folders, userArticleStates } from "../../data/db/schema.js";
import type { Database } from "../api/db.js";
import { isUuid, longItemKey, shortItemKey } from "./ids.js";
import {
  STATE_READING_LIST,
  STATE_READ,
  STATE_STARRED,
  feedStreamId,
  labelStreamId,
  stateStreamId,
  parseStreamId,
} from "./streams.js";
import type { ContinuationPayload } from "./cursor.js";
import { encodeContinuation } from "./cursor.js";

// greader data access, following the house style: inline drizzle queries
// scoped by feeds.userId (per-user feeds model), sparse read-state rows
// (absent row = unread + unstarred), NOT EXISTS subqueries for unread
// aggregates. No new service layer.
//
// Ranking/ordering/continuation is keyset on the item ARRIVAL timestamp
// (articles.created_at, microsecond-exact via EXTRACT(EPOCH)*1e6::BIGINT):
// stable across pages (no dup/drop), consistent with the timestampUsec values
// emitted to clients, and matching the BazQux-style arrival-time ot/nt
// semantics (feeds that backdate pubDates never hide items).

const OT_BACKWARD_SLACK_SEC = 120;

// Arrival-rank expression: microseconds since epoch of articles.created_at,
// exact at DB precision. Shared by ordering, ot/nt bounds, mark-all ts and
// the continuation keyset — every comparison happens on this same value.
export function arrivalRankSql(): SQL {
  return sql`FLOOR(EXTRACT(EPOCH FROM ${articles.createdAt}) * 1000000)::BIGINT`;
}

function rankRaw(): SQL {
  return arrivalRankSql();
}

// `substring(...) IN (k1, k2, ...)` condition over the canonical 16-hex
// item keys — the SQL side of the ids.ts uuid derivation.
export function hex16InCondition(keys: string[]): SQL {
  const hexExpr = sql`substring(replace(${articles.id}::text, '-', ''), 1, 16)`;
  const keyList = sql.join(
    keys.map((key) => sql`${key}`),
    sql`, `
  );
  return sql`${hexExpr} IN (${keyList})`;
}

function unreadSubquery(userId: string): SQL {
  return sql`EXISTS (
    SELECT 1 FROM ${userArticleStates}
    WHERE ${userArticleStates.articleId} = ${articles.id}
    AND ${userArticleStates.userId} = ${userId}
    AND ${userArticleStates.isRead} = true
  )`;
}

export type ResolvedStream =
  | { kind: "all" }
  | { kind: "read" }
  | { kind: "starred" }
  | { kind: "folder"; folderId: string; name: string }
  | { kind: "feed"; feedId: string; url: string };

// null = malformed grammar (400); "unknown" = valid grammar but no such
// feed/label for this user (callers serve an empty page, like FreshRSS).
// State/label ids go through parseStreamId so ANY user-id segment is
// accepted (SPEC 3.2: user/-/... and user/12345/... are the same stream —
// NetNewsWire sends the numeric form).
export async function resolveStream(
  db: Database,
  userId: string,
  stream: string
): Promise<ResolvedStream | "unknown" | null> {
  const parsed = parseStreamId(stream);
  if (parsed?.kind === "state") {
    if (parsed.state === STATE_READING_LIST) return { kind: "all" };
    if (parsed.state === STATE_READ) return { kind: "read" };
    return { kind: "starred" };
  }

  if (parsed?.kind === "label") {
    const [folder] = await db
      .select({ id: folders.id, name: folders.name })
      .from(folders)
      .where(and(eq(folders.userId, userId), eq(folders.name, parsed.name)))
      .limit(1);
    return folder ? { kind: "folder", folderId: folder.id, name: folder.name } : "unknown";
  }

  if (stream.startsWith("feed/") || /^https?:\/\//.test(stream) || isUuid(stream)) {
    const token = stream.startsWith("feed/") ? stream.slice("feed/".length) : stream;
    if (!token) {
      return null;
    }
    return (await resolveFeedToken(db, userId, token)) ?? "unknown";
  }

  return null;
}

// Path-form stream ids arrive with one slash of "://" collapsed (the router
// drops empty path segments), so URL matches try the raw token and the
// repaired variant.
function feedUrlCandidates(token: string): string[] {
  const out = [token];
  const repaired = token.replace(/^(https?):\/([^/])/, "$1://$2");
  if (repaired !== token) {
    out.push(repaired);
  }
  return out;
}

async function resolveFeedToken(
  db: Database,
  userId: string,
  token: string
): Promise<{ kind: "feed"; feedId: string; url: string } | null> {
  if (isUuid(token)) {
    const [feed] = await db
      .select({ id: feeds.id, url: feeds.url })
      .from(feeds)
      .where(and(eq(feeds.id, token), eq(feeds.userId, userId)))
      .limit(1);
    return feed ? { kind: "feed", feedId: feed.id, url: feed.url } : null;
  }
  const [feed] = await db
    .select({ id: feeds.id, url: feeds.url })
    .from(feeds)
    .where(and(eq(feeds.userId, userId), inArray(feeds.url, feedUrlCandidates(token))))
    .limit(1);
  return feed ? { kind: "feed", feedId: feed.id, url: feed.url } : null;
}

export type StreamTagFilter =
  | { type: "read" }
  | { type: "starred" }
  | { type: "folder"; folderId: string };

export async function resolveStreamTag(
  db: Database,
  userId: string,
  tag: string
): Promise<StreamTagFilter | "unknown" | null> {
  const parsed = parseStreamId(tag);
  if (parsed?.kind === "state") {
    if (parsed.state === STATE_READ) return { type: "read" };
    if (parsed.state === STATE_STARRED) return { type: "starred" };
    return null;
  }
  if (parsed?.kind === "label") {
    const [folder] = await db
      .select({ id: folders.id })
      .from(folders)
      .where(and(eq(folders.userId, userId), eq(folders.name, parsed.name)))
      .limit(1);
    return folder ? { type: "folder", folderId: folder.id } : "unknown";
  }
  return null;
}

function tagFilterCondition(filter: StreamTagFilter, mode: "exclude" | "include"): SQL {
  switch (filter.type) {
    case "read":
      return mode === "include"
        ? eq(userArticleStates.isRead, true)
        : sql`(${userArticleStates.isRead} = false OR ${userArticleStates.isRead} IS NULL)`;
    case "starred":
      return mode === "include"
        ? eq(userArticleStates.isStarred, true)
        : sql`(${userArticleStates.isStarred} = false OR ${userArticleStates.isStarred} IS NULL)`;
    case "folder":
      return mode === "include"
        ? eq(feeds.folderId, filter.folderId)
        : sql`(${feeds.folderId} IS NULL OR ${feeds.folderId} <> ${filter.folderId})`;
  }
}

export interface StreamQueryOptions {
  n: number;
  ascending: boolean;
  otSec: number | null;
  ntSec: number | null;
  cursor: ContinuationPayload | null;
}

export type XtIt = StreamTagFilter | "unknown" | null;

function streamConditions(userId: string, stream: ResolvedStream): SQL[] {
  const conds: SQL[] = [eq(feeds.userId, userId) as SQL];
  if (stream.kind === "feed") {
    conds.push(eq(articles.feedId, stream.feedId) as SQL);
  } else if (stream.kind === "folder") {
    conds.push(eq(feeds.folderId, stream.folderId) as SQL);
  } else if (stream.kind === "read") {
    conds.push(eq(userArticleStates.isRead, true) as SQL);
  } else if (stream.kind === "starred") {
    conds.push(eq(userArticleStates.isStarred, true) as SQL);
  }
  return conds;
}

function timeAndCursorConditions(opts: StreamQueryOptions): SQL[] {
  const conds: SQL[] = [];
  if (opts.otSec !== null && Number.isFinite(opts.otSec)) {
    const bound = String(Math.round((opts.otSec - OT_BACKWARD_SLACK_SEC) * 1e6));
    conds.push(sql`${rankRaw()} >= ${bound}::bigint`);
  }
  if (opts.ntSec !== null && Number.isFinite(opts.ntSec)) {
    const bound = String(Math.round(opts.ntSec * 1e6));
    conds.push(sql`${rankRaw()} <= ${bound}::bigint`);
  }
  if (opts.cursor) {
    conds.push(
      opts.cursor.o === "a"
        ? sql`(${rankRaw()} > ${opts.cursor.r}::bigint OR (${rankRaw()} = ${opts.cursor.r}::bigint AND ${articles.id} > ${opts.cursor.i}::uuid))`
        : sql`(${rankRaw()} < ${opts.cursor.r}::bigint OR (${rankRaw()} = ${opts.cursor.r}::bigint AND ${articles.id} < ${opts.cursor.i}::uuid))`
    );
  }
  return conds;
}

export interface ItemRow {
  hex16: string;
  id: string;
  rankUsec: string;
  title: string;
  url: string;
  author: string | null;
  content: string | null;
  summary: string | null;
  publishedAt: Date | null;
  enclosures: unknown;
  isRead: boolean | null;
  isStarred: boolean | null;
  feedUrl: string;
  feedTitle: string;
  feedCustomTitle: string | null;
  feedSiteUrl: string | null;
  folderName: string | null;
}

function itemQuery(db: Database, userId: string) {
  return db
    .select({
      hex16: sql<string>`substring(replace(${articles.id}::text, '-', ''), 1, 16)`.as("hex16"),
      id: articles.id,
      rankUsec: sql<string>`FLOOR(EXTRACT(EPOCH FROM ${articles.createdAt}) * 1000000)::BIGINT`.as("rankUsec"),
      title: articles.title,
      url: articles.url,
      author: articles.author,
      content: articles.content,
      summary: articles.summary,
      publishedAt: articles.publishedAt,
      enclosures: articles.enclosures,
      isRead: userArticleStates.isRead,
      isStarred: userArticleStates.isStarred,
      feedUrl: feeds.url,
      feedTitle: feeds.title,
      feedCustomTitle: feeds.customTitle,
      feedSiteUrl: feeds.siteUrl,
      folderName: folders.name,
    })
    .from(articles)
    .innerJoin(feeds, eq(articles.feedId, feeds.id))
    .leftJoin(folders, eq(feeds.folderId, folders.id))
    .leftJoin(
      userArticleStates,
      and(eq(userArticleStates.articleId, articles.id), eq(userArticleStates.userId, userId))
    );
}

function emptyPage<T>(): { rows: T[]; continuation: string | null } {
  return { rows: [], continuation: null };
}

// xt/it = "unknown" (valid grammar, no such tag target) is an unsatisfiable
// filter: for xt (exclude) it excludes nothing special — but the tag does not
// exist, so Google-era behavior is to return the stream unfiltered. FreshRSS
// ignores unknown filters. We ignore too (treat as absent).
function applyTagFilters(conds: SQL[], xt: XtIt, it: XtIt): void {
  if (xt && xt !== "unknown") {
    conds.push(tagFilterCondition(xt, "exclude"));
  }
  if (it && it !== "unknown") {
    conds.push(tagFilterCondition(it, "include"));
  }
}

// Paged full items for stream/contents. Fetches n+1; the continuation is
// emitted only when the extra row exists, keyed on the last EMITTED row.
export async function queryStreamItems(
  db: Database,
  userId: string,
  stream: ResolvedStream,
  xt: XtIt,
  it: XtIt,
  opts: StreamQueryOptions
): Promise<{ rows: ItemRow[]; continuation: string | null }> {
  const conds = streamConditions(userId, stream);
  applyTagFilters(conds, xt, it);
  conds.push(...timeAndCursorConditions(opts));

  const rank = rankRaw();
  const fetched = await itemQuery(db, userId)
    .where(and(...conds))
    .orderBy(
      ...(opts.ascending
        ? [asc(rank), asc(articles.id)]
        : [desc(rank), desc(articles.id)])
    )
    .limit(opts.n + 1);

  return finishPage(fetched as unknown as ItemRow[], opts);
}

function finishPage<T extends { rankUsec: string; id: string }>(
  fetched: T[],
  opts: StreamQueryOptions
): { rows: T[]; continuation: string | null } {
  if (fetched.length <= opts.n) {
    return { rows: fetched, continuation: null };
  }
  const rows = fetched.slice(0, opts.n);
  const last = rows[rows.length - 1];
  return {
    rows,
    continuation: encodeContinuation({
      o: opts.ascending ? "a" : "d",
      r: last.rankUsec,
      i: last.id,
    }),
  };
}

export interface ItemRef {
  id: string;
  timestampUsec: string;
  directStreamIds?: string[];
}

// Paged id refs for stream/items/ids — short signed decimal ids (the one
// place the short form is mandatory), timestampUsec always included,
// directStreamIds only when the client asks.
export async function queryStreamItemRefs(
  db: Database,
  userId: string,
  stream: ResolvedStream,
  xt: XtIt,
  it: XtIt,
  opts: StreamQueryOptions,
  includeDirectStreamIds: boolean
): Promise<{ refs: ItemRef[]; continuation: string | null }> {
  const conds = streamConditions(userId, stream);
  applyTagFilters(conds, xt, it);
  conds.push(...timeAndCursorConditions(opts));

  const rank = rankRaw();
  const fetched = (await db
    .select({
      hex16: sql<string>`substring(replace(${articles.id}::text, '-', ''), 1, 16)`.as("hex16"),
      id: articles.id,
      rankUsec: sql<string>`FLOOR(EXTRACT(EPOCH FROM ${articles.createdAt}) * 1000000)::BIGINT`.as("rankUsec"),
      feedUrl: feeds.url,
    })
    .from(articles)
    .innerJoin(feeds, eq(articles.feedId, feeds.id))
    .leftJoin(
      userArticleStates,
      and(eq(userArticleStates.articleId, articles.id), eq(userArticleStates.userId, userId))
    )
    .where(and(...conds))
    .orderBy(
      ...(opts.ascending ? [asc(rank), asc(articles.id)] : [desc(rank), desc(articles.id)])
    )
    .limit(opts.n + 1)) as Array<{ hex16: string; id: string; rankUsec: string; feedUrl: string }>;

  const { rows, continuation } = finishPage(fetched, opts);
  return {
    refs: rows.map((row) => ({
      id: shortItemKey(row.hex16),
      timestampUsec: row.rankUsec,
      ...(includeDirectStreamIds ? { directStreamIds: [feedStreamId(row.feedUrl)] } : {}),
    })),
    continuation,
  };
}

// greader item JSON. Long-form ids; Msec/Usec as STRINGS; published as a
// NUMBER (house Date semantics); summary.content carries the HTML (NNW reads
// summary only); read/starred state expressed through categories.
export function itemToJson(row: ItemRow): Record<string, unknown> {
  const rankUsec = row.rankUsec || "0";
  const crawlTimeMsec = (BigInt(rankUsec) / 1000n).toString();
  const published = row.publishedAt
    ? Math.floor(row.publishedAt.getTime() / 1000)
    : Number(BigInt(rankUsec) / 1000000n);
  const html = row.content || row.summary || "";
  const categories = [stateStreamId(STATE_READING_LIST)];
  if (row.folderName) {
    categories.push(labelStreamId(row.folderName));
  }
  if (row.isRead === true) {
    categories.push(stateStreamId(STATE_READ));
  }
  if (row.isStarred === true) {
    categories.push(stateStreamId(STATE_STARRED));
  }
  const enclosures = Array.isArray(row.enclosures)
    ? (row.enclosures as Array<{ url?: string; type?: string; length?: string | number }>)
        .filter((e) => e && typeof e.url === "string")
        .map((e) => ({
          href: e.url as string,
          type: e.type ?? "",
          ...(e.length !== undefined ? { length: e.length } : {}),
        }))
    : [];
  return {
    id: longItemKey(row.hex16),
    crawlTimeMsec,
    timestampUsec: rankUsec,
    published,
    title: row.title,
    canonical: [{ href: row.url }],
    alternate: [{ href: row.url, type: "text/html" }],
    categories,
    origin: {
      streamId: feedStreamId(row.feedUrl),
      title: row.feedCustomTitle || row.feedTitle,
      htmlUrl: row.feedSiteUrl || "",
    },
    summary: { direction: "ltr", content: html.length > 500000 ? html.slice(0, 500000) : html },
    ...(row.author ? { author: row.author } : {}),
    ...(enclosures.length > 0 ? { enclosure: enclosures } : {}),
  };
}

// items/contents lookups by canonical 16-hex keys (both wire forms already
// normalized by the caller). Unknown ids are omitted, never 404 (FreshRSS
// behavior). SQL prefix matching on the uuid: see ids.ts for the derivation.
export async function itemsByKeys(db: Database, userId: string, keys: string[]): Promise<ItemRow[]> {
  if (keys.length === 0) {
    return [];
  }
  return (await itemQuery(db, userId).where(
    and(eq(feeds.userId, userId) as SQL, hex16InCondition(keys))
  )) as unknown as ItemRow[];
}

export interface UnreadFeedRow {
  url: string;
  folderId: string | null;
  folderName: string | null;
  unread: number;
  newestUnread: string | null;
  newestAny: string | null;
}

export async function unreadFeedRows(db: Database, userId: string): Promise<UnreadFeedRow[]> {
  const unreadExists = unreadSubquery(userId);
  const rows = await db
    .select({
      url: feeds.url,
      folderId: feeds.folderId,
      folderName: folders.name,
      unread: sql<number>`
        COUNT(DISTINCT ${articles.id}) FILTER (
          WHERE ${articles.id} IS NOT NULL
          AND NOT ${unreadExists}
        )
      `.as("unread"),
      newestUnread: sql<string | null>`
        MAX(FLOOR(EXTRACT(EPOCH FROM ${articles.createdAt}) * 1000000)::BIGINT) FILTER (WHERE NOT ${unreadExists})
      `.as("newestUnread"),
      newestAny: sql<string | null>`
        MAX(FLOOR(EXTRACT(EPOCH FROM ${articles.createdAt}) * 1000000)::BIGINT)
      `.as("newestAny"),
    })
    .from(feeds)
    .leftJoin(articles, eq(articles.feedId, feeds.id))
    .leftJoin(folders, eq(feeds.folderId, folders.id))
    .where(eq(feeds.userId, userId))
    .groupBy(feeds.id, folders.name);
  return rows.map((row) => ({ ...row, unread: Number(row.unread) }));
}

export async function userFolders(db: Database, userId: string): Promise<Array<{ id: string; name: string }>> {
  return db
    .select({ id: folders.id, name: folders.name })
    .from(folders)
    .where(eq(folders.userId, userId))
    .orderBy(folders.position, folders.name);
}

export interface SubscriptionRow {
  url: string;
  title: string;
  customTitle: string | null;
  siteUrl: string | null;
  favicon: string | null;
  folderName: string | null;
}

export async function subscriptionRows(db: Database, userId: string): Promise<SubscriptionRow[]> {
  return db
    .select({
      url: feeds.url,
      title: feeds.title,
      customTitle: feeds.customTitle,
      siteUrl: feeds.siteUrl,
      favicon: feeds.favicon,
      folderName: folders.name,
    })
    .from(feeds)
    .leftJoin(folders, eq(feeds.folderId, folders.id))
    .where(eq(feeds.userId, userId))
    .orderBy(feeds.customTitle, feeds.title);
}
