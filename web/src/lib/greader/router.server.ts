import bcrypt from "bcrypt";
import { eq, and, or, sql, inArray, type SQL } from "drizzle-orm";
import Parser from "rss-parser";
import { articles, feeds, folders, userArticleStates, users } from "../../data/db/schema.js";
import { getDb } from "../api/db.js";
import { AppError } from "../api/errors.js";
import {
  authRateLimitKey,
  consumeAuthRateLimit,
  consumeAnonAuthRateLimit,
} from "../api/rate-limit.js";
import { signGreaderAuthToken, signGreaderPostToken } from "../api/tokens.js";
import { getDataRuntime } from "../../data/runtime.js";
import { fetchFeedXml } from "../../services/feed-fetch.js";
import { faviconUrlFor } from "../favicon.js";
import { verifyGreaderPostToken, type GreaderUser } from "./auth.js";
import {
  greaderJsonResponse,
  greaderOk,
  greaderTextResponse,
  greaderErrorResponse,
  readGreaderParams,
  type GreaderParams,
} from "./http.js";
import { parseItemKey } from "./ids.js";
import {
  feedStreamId,
  labelStreamId,
  stateStreamId,
  parseEditTag,
} from "./streams.js";
import { decodeContinuation, type ContinuationPayload } from "./cursor.js";
import {
  arrivalRankSql,
  hex16InCondition,
  itemsByKeys,
  queryStreamItemRefs,
  queryStreamItems,
  resolveStream,
  resolveStreamTag,
  subscriptionRows,
  unreadFeedRows,
  userFolders,
  itemToJson,
  type ResolvedStream,
  type StreamQueryOptions,
  type XtIt,
} from "./queries.js";

// greader (Google Reader compatible) API: one catch-all router. The path
// grammar is deep and fixed (accounts/ClientLogin, reader/api/0/<endpoint>
// with stream-id PATH segments like stream/contents/feed/<url>), so dispatch
// switches on the decoded splat instead of the filesystem.
//
// Conventions (SPEC): form-urlencoded bodies via readGreaderParams (getAll
// everywhere — repeated i=/a= keys), JSON by default, text/plain "OK" for
// mutations, loaders THROW their Responses (greaderHandleLoader mirrors
// errors.ts handleLoader), errors as short text bodies with real statuses.

const READER_PREFIX = "reader/api/0/";

const parser = new Parser();

// Same dummy hash as the login route: compared on the missing-user path so
// response timings match the real-password path (no account oracle).
const DUMMY_PASSWORD_HASH = "$2b$10$Y7pIF/8wk8MbFgVY2xRAYe7ta9sU1Os7PMqw5Z.IAAWY4/7DsiHAG";

async function greaderHandle(fn: () => Promise<Response>): Promise<Response> {
  try {
    return await fn();
  } catch (error) {
    return greaderErrorResponse(error);
  }
}

// The dev runtime hands the splat percent-encoded; the production runtime
// hands it decoded (the router decodes the whole pathname, collapsing one
// slash of "://"). Decoding here is a no-op in production and repairs dev;
// feed-id resolution additionally repairs the collapsed-slash form.
function decodeSplat(raw: string): string {
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}

async function dispatch(
  request: Request,
  params: Record<string, string>,
  context: Record<string, unknown>
): Promise<Response> {
  const path = decodeSplat((params.path ?? "").replace(/^\/+/, ""));

  if (path === "accounts/ClientLogin") {
    return handleClientLogin(request);
  }

  if (!path.startsWith(READER_PREFIX)) {
    return greaderTextResponse("Not Found", 404);
  }
  const endpoint = path.slice(READER_PREFIX.length);

  switch (true) {
    case endpoint === "user-info":
      return handleUserInfo(context);
    case endpoint === "token":
      return handleToken(context);
    case endpoint === "subscription/list":
      return handleSubscriptionList(context);
    case endpoint === "subscription/quickadd":
      return handleQuickAdd(request, context);
    case endpoint === "subscription/edit":
      return handleSubscriptionEdit(request, context);
    case endpoint === "tag/list":
      return handleTagList(context);
    case endpoint === "unread-count":
      return handleUnreadCount(context);
    case endpoint === "stream/items/ids":
      return handleStreamItemIds(request, context);
    case endpoint === "stream/items/contents":
      return handleStreamItemsContents(request, context);
    case endpoint === "stream/contents" || endpoint.startsWith("stream/contents/"):
      return handleStreamContents(request, endpoint, context);
    case endpoint === "edit-tag":
      return handleEditTag(request, context);
    case endpoint === "mark-all-as-read":
      return handleMarkAllRead(request, context);
    case endpoint === "rename-tag":
      return handleRenameTag(request, context);
    case endpoint === "disable-tag":
      return handleDisableTag(request, context);
    default:
      // Includes the deliberate 2.16 not-implemented set (OPML import/export,
      // preferences, search, social, splice streams).
      return greaderTextResponse("Not Found", 404);
  }
}

function needUser(context: Record<string, unknown>): GreaderUser {
  const user = context.user as GreaderUser | undefined;
  if (!user) {
    throw new AppError("Not authenticated", 401);
  }
  return user;
}

// ---------------------------------------------------------------------------
// Auth endpoints
// ---------------------------------------------------------------------------

function badAuthentication(): Response {
  return greaderTextResponse("Error=BadAuthentication\n", 401);
}

async function handleClientLogin(request: Request): Promise<Response> {
  const form = await readGreaderParams(request);
  const email = form.get("Email");
  const passwd = form.get("Passwd");
  if (!email || passwd === null) {
    return greaderTextResponse("Error=BadAuthentication\n", 400);
  }

  // Shares the fail-closed 5/15min auth budget with web login.
  const clientKey = authRateLimitKey(request);
  if (clientKey !== null) {
    await consumeAuthRateLimit(clientKey);
  } else {
    await consumeAnonAuthRateLimit(email);
  }

  const db = await getDb();
  const [user] = await db
    .select()
    .from(users)
    .where(or(eq(users.email, email), eq(users.username, email)))
    .limit(1);

  if (!user) {
    await bcrypt.compare(passwd, DUMMY_PASSWORD_HASH);
    return badAuthentication();
  }
  if (!user.isActive) {
    return badAuthentication();
  }
  const validPassword = await bcrypt.compare(passwd, user.passwordHash || "");
  if (!validPassword) {
    return badAuthentication();
  }

  await db
    .update(users)
    .set({ lastLoginAt: new Date() })
    .where(eq(users.id, user.id));

  const tokenVersion = user.tokenVersion ?? 0;
  const authToken = signGreaderAuthToken(user.id, user.email, user.username, user.role, tokenVersion);
  console.info(`greader ClientLogin: user ${user.id}`);
  // SID/LSID values are never used by target clients; the Auth line is the
  // only one kept. LSID exists because Vienna RSS requires the line.
  return greaderTextResponse(`SID=${authToken}\nLSID=null\nAuth=${authToken}\n`);
}

function handleToken(context: Record<string, unknown>): Response {
  const user = needUser(context);
  return greaderTextResponse(`${signGreaderPostToken(user.id, user.tokenVersion)}\n`);
}

function handleUserInfo(context: Record<string, unknown>): Response {
  const user = needUser(context);
  return greaderJsonResponse({
    userId: user.id,
    userName: user.username,
    userProfileId: user.id,
    userEmail: user.email,
    isBloggerUser: false,
    signupTimeSec: Math.floor(user.createdAt.getTime() / 1000),
    isMultiLoginEnabled: false,
  });
}

// ---------------------------------------------------------------------------
// Subscriptions and tags
// ---------------------------------------------------------------------------

function sortid(index: number): string {
  return (0x10000000 + index).toString(16).toUpperCase().padStart(8, "0");
}

async function handleSubscriptionList(context: Record<string, unknown>): Promise<Response> {
  const user = needUser(context);
  const db = await getDb();
  const rows = await subscriptionRows(db, user.id);
  return greaderJsonResponse({
    subscriptions: rows.map((row, index) => ({
      id: feedStreamId(row.url),
      title: row.customTitle || row.title,
      categories: row.folderName ? [{ id: labelStreamId(row.folderName), label: row.folderName }] : [],
      sortid: sortid(index),
      ...(row.favicon ? { iconUrl: row.favicon } : {}),
      url: row.url,
      htmlUrl: row.siteUrl || "",
    })),
  });
}

async function handleTagList(context: Record<string, unknown>): Promise<Response> {
  const user = needUser(context);
  const db = await getDb();
  const folderRows = await userFolders(db, user.id);
  const tags = [
    { id: stateStreamId("starred"), sortid: sortid(0) },
    { id: stateStreamId("reading-list"), sortid: sortid(1) },
    ...folderRows.map((folder, index) => ({
      id: labelStreamId(folder.name),
      sortid: sortid(index + 2),
    })),
  ];
  return greaderJsonResponse({ tags });
}

async function handleUnreadCount(context: Record<string, unknown>): Promise<Response> {
  const user = needUser(context);
  const db = await getDb();
  const rows = await unreadFeedRows(db, user.id);
  const folderRows = await userFolders(db, user.id);

  const unreadcounts: Array<{ id: string; count: number; newestItemTimestampUsec: string }> = [];
  let total = 0;
  let newestTotal = "0";
  for (const row of rows) {
    total += row.unread;
    const newest = row.newestUnread || row.newestAny || "0";
    if (BigInt(newest) > BigInt(newestTotal)) {
      newestTotal = newest;
    }
    unreadcounts.push({ id: feedStreamId(row.url), count: row.unread, newestItemTimestampUsec: newest });
  }
  for (const folder of folderRows) {
    const memberRows = rows.filter((row) => row.folderId === folder.id);
    const count = memberRows.reduce((sum, row) => sum + row.unread, 0);
    const newest = memberRows.reduce((max, row) => {
      const value = row.newestUnread || row.newestAny || "0";
      return BigInt(value) > BigInt(max) ? value : max;
    }, "0");
    unreadcounts.push({ id: labelStreamId(folder.name), count, newestItemTimestampUsec: newest });
  }
  unreadcounts.push({ id: stateStreamId("reading-list"), count: total, newestItemTimestampUsec: newestTotal });

  return greaderJsonResponse({ max: 1000, unreadcounts });
}

// ---------------------------------------------------------------------------
// Item streams
// ---------------------------------------------------------------------------

function parseCount(raw: string | null): number {
  const value = parseInt(raw ?? "", 10);
  if (!Number.isFinite(value)) {
    return 20;
  }
  return Math.min(Math.max(value, 1), 1000);
}

function parseSeconds(raw: string | null): number | null {
  if (raw === null || raw === "") {
    return null;
  }
  const value = Number(raw);
  return Number.isFinite(value) && value > 0 ? value : null;
}

function parseContinuation(raw: string | null): ContinuationPayload | null {
  if (raw === null || raw === "") {
    return null;
  }
  const payload = decodeContinuation(raw);
  if (!payload) {
    throw new AppError("Invalid continuation token", 400);
  }
  return payload;
}

interface StreamRequest {
  streamId: string;
  stream: ResolvedStream | "unknown";
  xt: XtIt;
  it: XtIt;
  opts: StreamQueryOptions;
}

async function parseStreamRequest(
  request: Request,
  context: Record<string, unknown>,
  fallbackStream?: string
): Promise<{ params: GreaderParams; req: StreamRequest }> {
  const user = needUser(context);
  const params = await readGreaderParams(request);
  const streamId = params.get("s") ?? fallbackStream ?? stateStreamId("reading-list");

  const db = await getDb();
  const stream = await resolveStream(db, user.id, streamId);
  if (stream === null) {
    throw new AppError("Invalid stream id", 400);
  }

  const xtTag = params.get("xt");
  const itTag = params.get("it");
  const xt = xtTag !== null && xtTag !== "" ? await resolveStreamTag(db, user.id, xtTag) : null;
  if (xtTag && xt === null) {
    throw new AppError("Invalid exclude tag", 400);
  }
  const it = itTag !== null && itTag !== "" ? await resolveStreamTag(db, user.id, itTag) : null;
  if (itTag && it === null) {
    throw new AppError("Invalid include tag", 400);
  }

  const opts: StreamQueryOptions = {
    n: parseCount(params.get("n")),
    ascending: params.get("r") === "o",
    otSec: parseSeconds(params.get("ot")),
    ntSec: parseSeconds(params.get("nt")),
    cursor: parseContinuation(params.get("c")),
  };

  return { params, req: { streamId, stream, xt, it, opts } };
}

async function handleStreamItemIds(request: Request, context: Record<string, unknown>): Promise<Response> {
  const user = needUser(context);
  const { params, req } = await parseStreamRequest(request, context);
  if (req.stream === "unknown") {
    return greaderJsonResponse({ itemRefs: [] });
  }
  const { refs, continuation } = await queryStreamItemRefs(
    await getDb(),
    user.id,
    req.stream,
    req.xt,
    req.it,
    req.opts,
    params.get("includeAllDirectStreamIds") === "true"
  );
  return greaderJsonResponse({
    itemRefs: refs,
    ...(continuation ? { continuation } : {}),
  });
}

async function handleStreamContents(
  request: Request,
  endpoint: string,
  context: Record<string, unknown>
): Promise<Response> {
  const user = needUser(context);
  // Three request forms: ?s=<id>, path suffix (feed/<url>, user/-/state/...,
  // user/-/label/<name> — decoded, so feed URLs arrive with one slash of
  // "://" collapsed; the resolver repairs), or bare (FeedMe) = reading-list.
  const pathStream = endpoint.slice("stream/contents".length).replace(/^\/+/, "");
  const { req } = await parseStreamRequest(request, context, pathStream || undefined);

  const canonicalId =
    req.stream === "unknown"
      ? req.streamId
      : req.stream.kind === "feed"
        ? feedStreamId(req.stream.url)
        : req.stream.kind === "folder"
          ? labelStreamId(req.stream.name)
          : stateStreamId(req.stream.kind === "all" ? "reading-list" : req.stream.kind);

  if (req.stream === "unknown") {
    return greaderJsonResponse({
      id: canonicalId,
      updated: Math.floor(Date.now() / 1000),
      items: [],
    });
  }

  const { rows, continuation } = await queryStreamItems(await getDb(), user.id, req.stream, req.xt, req.it, req.opts);
  return greaderJsonResponse({
    id: canonicalId,
    updated: Math.floor(Date.now() / 1000),
    ...(continuation ? { continuation } : {}),
    items: rows.map(itemToJson),
  });
}

async function handleStreamItemsContents(request: Request, context: Record<string, unknown>): Promise<Response> {
  const user = needUser(context);
  const params = await readGreaderParams(request);
  // i repeated, either id form, capped at 1000. T is accepted but not
  // required (NetNewsWire sends it; this is a read).
  const ids = params.getAll("i").slice(0, 1000);
  if (ids.length === 0) {
    throw new AppError("Missing item ids", 400);
  }
  const keys = ids.map((id) => {
    const key = parseItemKey(id);
    if (!key) {
      throw new AppError(`Invalid item id: ${id.slice(0, 32)}`, 400);
    }
    return key;
  });

  const db = await getDb();
  const rows = await itemsByKeys(db, user.id, keys);
  return greaderJsonResponse({
    id: stateStreamId("reading-list"),
    updated: Math.floor(Date.now() / 1000),
    items: rows.map(itemToJson),
  });
}

// ---------------------------------------------------------------------------
// State mutations
// ---------------------------------------------------------------------------

async function handleEditTag(request: Request, context: Record<string, unknown>): Promise<Response> {
  const user = needUser(context);
  const params = await readGreaderParams(request);
  const badToken = verifyGreaderPostToken(params, user);
  if (badToken) {
    return badToken;
  }

  const ids = params.getAll("i");
  if (ids.length === 0) {
    throw new AppError("Missing item ids", 400);
  }
  const keys: string[] = [];
  for (const id of ids) {
    const key = parseItemKey(id);
    if (!key) {
      throw new AppError(`Invalid item id: ${id.slice(0, 32)}`, 400);
    }
    keys.push(key);
  }

  let isRead: boolean | undefined;
  let isStarred: boolean | undefined;
  for (const tag of params.getAll("a")) {
    const parsed = parseEditTag(tag);
    if (!parsed) {
      throw new AppError("Invalid tag", 400);
    }
    if (parsed.kind === "read") isRead = true;
    if (parsed.kind === "starred") isStarred = true;
  }
  for (const tag of params.getAll("r")) {
    const parsed = parseEditTag(tag);
    if (!parsed) {
      throw new AppError("Invalid tag", 400);
    }
    if (parsed.kind === "read") isRead = false;
    if (parsed.kind === "starred") isStarred = false;
  }
  if (isRead === undefined && isStarred === undefined) {
    // Only no-op tags (kept-unread/broadcast/labels) — accept without writes.
    return greaderOk();
  }

  const db = await getDb();
  const owned = await db
    .select({ id: articles.id })
    .from(articles)
    .innerJoin(feeds, eq(articles.feedId, feeds.id))
    .where(and(eq(feeds.userId, user.id) as SQL, hex16InCondition(keys)));
  const ownedIds = owned.map((row) => row.id);
  if (ownedIds.length === 0) {
    return greaderOk();
  }

  // Ownership-filtered upsert, batch-update route pattern (every column,
  // table order; unspecified fields carry through COALESCE/EXCLUDED).
  const isReadExpr = isRead === undefined ? sql`COALESCE(${userArticleStates.isRead}, false)` : sql`${isRead}`;
  const readAtExpr =
    isRead === true ? sql`now()` : isRead === false ? sql`NULL` : sql`${userArticleStates.readAt}`;
  const isStarredExpr =
    isStarred === undefined ? sql`COALESCE(${userArticleStates.isStarred}, false)` : sql`${isStarred}`;
  const starredAtExpr =
    isStarred === true ? sql`now()` : isStarred === false ? sql`NULL` : sql`${userArticleStates.starredAt}`;

  await db
    .insert(userArticleStates)
    .select(
      db
        .select({
          userId: sql`${user.id}::uuid`.as("userId"),
          articleId: articles.id,
          isRead: isReadExpr.as("isRead"),
          isStarred: isStarredExpr.as("isStarred"),
          readAt: readAtExpr.as("readAt"),
          starredAt: starredAtExpr.as("starredAt"),
          readingTime: userArticleStates.readingTime,
          createdAt: sql`now()`.as("createdAt"),
          updatedAt: sql`now()`.as("updatedAt"),
        })
        .from(articles)
        .innerJoin(feeds, eq(articles.feedId, feeds.id))
        .leftJoin(
          userArticleStates,
          and(eq(userArticleStates.articleId, articles.id), eq(userArticleStates.userId, user.id))
        )
        .where(and(inArray(articles.id, ownedIds), eq(feeds.userId, user.id)))
    )
    .onConflictDoUpdate({
      target: [userArticleStates.userId, userArticleStates.articleId],
      set: {
        isRead: sql`excluded.is_read`,
        readAt: sql`excluded.read_at`,
        isStarred: sql`excluded.is_starred`,
        starredAt: sql`excluded.starred_at`,
        updatedAt: sql`excluded.updated_at`,
      },
    });

  return greaderOk();
}

// ts is MICROseconds (mark only items older, inclusive). Values longer than
// 17 digits are treated as nanoseconds and truncated to usec (SPEC OQ2).
function parseTsUsec(raw: string | null): string | null {
  if (raw === null || raw === "") {
    return null;
  }
  if (!/^\d+$/.test(raw)) {
    throw new AppError("Invalid ts", 400);
  }
  return raw.length > 17 ? raw.slice(0, raw.length - 3) : raw;
}

async function handleMarkAllRead(request: Request, context: Record<string, unknown>): Promise<Response> {
  const user = needUser(context);
  const params = await readGreaderParams(request);
  const badToken = verifyGreaderPostToken(params, user);
  if (badToken) {
    return badToken;
  }

  const streamId = params.get("s");
  if (!streamId) {
    throw new AppError("Missing stream id", 400);
  }
  const tsUsec = parseTsUsec(params.get("ts"));

  const db = await getDb();
  const stream = await resolveStream(db, user.id, streamId);
  if (stream === null) {
    throw new AppError("Invalid stream id", 400);
  }
  if (stream === "unknown") {
    return greaderOk();
  }

  const conditions: SQL[] = [
    eq(feeds.userId, user.id) as SQL,
    sql`(${userArticleStates.isRead} = false OR ${userArticleStates.isRead} IS NULL)`,
  ];
  if (stream.kind === "feed") {
    conditions.push(eq(articles.feedId, stream.feedId) as SQL);
  } else if (stream.kind === "folder") {
    conditions.push(eq(feeds.folderId, stream.folderId) as SQL);
  }
  if (tsUsec !== null) {
    conditions.push(sql`${arrivalRankSql()} <= ${tsUsec}::bigint`);
  }

  // Insert-select upsert, mark-all-read route pattern (every column, table
  // order).
  await db
    .insert(userArticleStates)
    .select(
      db
        .select({
          userId: sql`${user.id}::uuid`.as("userId"),
          articleId: articles.id,
          isRead: sql`true`.as("isRead"),
          isStarred: sql`COALESCE(${userArticleStates.isStarred}, false)`.as("isStarred"),
          readAt: sql`now()`.as("readAt"),
          starredAt: userArticleStates.starredAt,
          readingTime: userArticleStates.readingTime,
          createdAt: sql`now()`.as("createdAt"),
          updatedAt: sql`now()`.as("updatedAt"),
        })
        .from(articles)
        .innerJoin(feeds, eq(articles.feedId, feeds.id))
        .leftJoin(
          userArticleStates,
          and(eq(userArticleStates.articleId, articles.id), eq(userArticleStates.userId, user.id))
        )
        .where(and(...conditions))
    )
    .onConflictDoUpdate({
      target: [userArticleStates.userId, userArticleStates.articleId],
      set: {
        isRead: true,
        readAt: new Date(),
        updatedAt: new Date(),
      },
    });

  return greaderOk();
}

// ---------------------------------------------------------------------------
// Subscription mutations
// ---------------------------------------------------------------------------

// The POST /api/feeds subscribe path: SSRF-guarded fetch (assertSafeFeedUrl
// runs inside fetchFeedXml), rss-parser, per-user dup check, insert, enqueue
// the worker backfill. quickadd carries no BYO headers, so there is nothing
// for validateHttpHeaders to check.
async function subscribeFeed(
  userId: string,
  url: string,
  customTitle?: string,
  folderId?: string | null
): Promise<{ feed: typeof feeds.$inferSelect } | null> {
  const db = await getDb();
  const [existing] = await db
    .select({ id: feeds.id })
    .from(feeds)
    .where(and(eq(feeds.url, url), eq(feeds.userId, userId)))
    .limit(1);
  if (existing) {
    return null;
  }

  let feedData;
  try {
    feedData = await parser.parseString(await fetchFeedXml(url));
  } catch {
    return null;
  }

  const feedImage = feedData.image as string | { url?: string } | undefined;
  const [feed] = await db
    .insert(feeds)
    .values({
      userId,
      url,
      title: feedData.title || "Untitled Feed",
      description: feedData.description,
      siteUrl: feedData.link,
      imageUrl: typeof feedImage === "string" ? feedImage : feedImage?.url,
      customTitle: customTitle || undefined,
      folderId: folderId ?? undefined,
      favicon: faviconUrlFor(feedData.link),
    })
    .returning();

  const runtime = await getDataRuntime();
  await runtime.queue.add("feed.update-single", { feedId: feed.id });
  return { feed };
}

async function resolveOrCreateFolder(userId: string, name: string): Promise<string> {
  const db = await getDb();
  const [existing] = await db
    .select({ id: folders.id })
    .from(folders)
    .where(and(eq(folders.userId, userId), eq(folders.name, name)))
    .limit(1);
  if (existing) {
    return existing.id;
  }
  const [maxPosition] = await db
    .select({ max: sql<number>`MAX(${folders.position})` })
    .from(folders)
    .where(eq(folders.userId, userId));
  const [created] = await db
    .insert(folders)
    .values({ userId, name, position: Number(maxPosition?.max || 0) + 1 })
    .returning({ id: folders.id });
  return created.id;
}

function parseLabelTag(tag: string | null): string | null | undefined {
  if (tag === null || tag === "") {
    return undefined;
  }
  const match = tag.match(/^user\/[^/]+\/label\/(.+)$/);
  return match ? match[1] : null;
}

async function handleQuickAdd(request: Request, context: Record<string, unknown>): Promise<Response> {
  const user = needUser(context);
  const params = await readGreaderParams(request);
  const badToken = verifyGreaderPostToken(params, user);
  if (badToken) {
    return badToken;
  }

  const query = (params.get("quickadd") ?? "").trim();
  const url = query.startsWith("feed/") ? query.slice("feed/".length) : query;
  if (!/^https?:\/\//.test(url)) {
    return greaderJsonResponse({ query, numResults: 0, error: "invalid url" });
  }

  const result = await subscribeFeed(user.id, url);
  if (!result) {
    const db = await getDb();
    const [existing] = await db
      .select({ url: feeds.url, title: feeds.title })
      .from(feeds)
      .where(and(eq(feeds.url, url), eq(feeds.userId, user.id)))
      .limit(1);
    if (existing) {
      return greaderJsonResponse({ query, numResults: 0, error: "already subscribed" });
    }
    return greaderJsonResponse({ query, numResults: 0, error: "unable to fetch or parse feed" });
  }

  // streamId MUST be byte-identical to subscription/list ids (NNW joins by
  // raw string equality).
  return greaderJsonResponse({
    query,
    numResults: 1,
    streamId: feedStreamId(result.feed.url),
    streamName: result.feed.title,
  });
}

async function handleSubscriptionEdit(request: Request, context: Record<string, unknown>): Promise<Response> {
  const user = needUser(context);
  const params = await readGreaderParams(request);
  const badToken = verifyGreaderPostToken(params, user);
  if (badToken) {
    return badToken;
  }

  const actionName = params.get("ac");
  if (actionName !== "subscribe" && actionName !== "unsubscribe" && actionName !== "edit") {
    throw new AppError("Invalid ac", 400);
  }
  const streamIds = params.getAll("s");
  if (streamIds.length === 0) {
    throw new AppError("Missing stream id", 400);
  }
  const title = params.get("t");
  const addLabel = parseLabelTag(params.get("a"));
  if (params.get("a") && addLabel === null) {
    throw new AppError("Invalid a tag", 400);
  }
  const removeLabel = parseLabelTag(params.get("r"));
  if (params.get("r") && removeLabel === null) {
    throw new AppError("Invalid r tag", 400);
  }

  const db = await getDb();
  const addFolderId = addLabel ? await resolveOrCreateFolder(user.id, addLabel) : undefined;
  const removeFolderId = removeLabel
    ? (
        await db
          .select({ id: folders.id })
          .from(folders)
          .where(and(eq(folders.userId, user.id), eq(folders.name, removeLabel)))
          .limit(1)
      )[0]?.id
    : undefined;

  for (const streamId of streamIds) {
    const stream = await resolveStream(db, user.id, streamId);
    if (stream === null) {
      throw new AppError("Invalid stream id", 400);
    }

    if (actionName === "subscribe") {
      const token = streamId.startsWith("feed/") ? streamId.slice("feed/".length) : streamId;
      if (stream !== "unknown") {
        continue;
      }
      const result = await subscribeFeed(user.id, token, title ?? undefined, addFolderId ?? null);
      if (!result) {
        throw new AppError("Unable to subscribe to feed", 400);
      }
      continue;
    }

    if (stream === "unknown" || stream.kind !== "feed") {
      throw new AppError("Feed not found", 400);
    }
    const feedId = stream.feedId;

    if (actionName === "unsubscribe") {
      await db.delete(feeds).where(and(eq(feeds.id, feedId), eq(feeds.userId, user.id)));
      continue;
    }

    // edit: rename and/or move. One-folder model: a = set/move; without a,
    // r removes from the named folder (move to root).
    const patch: Record<string, unknown> = { updatedAt: new Date() };
    if (title !== null && title !== "") {
      patch.customTitle = title;
    }
    if (addFolderId !== undefined) {
      patch.folderId = addFolderId;
    } else if (removeFolderId !== undefined) {
      const [current] = await db
        .select({ folderId: feeds.folderId })
        .from(feeds)
        .where(and(eq(feeds.id, feedId), eq(feeds.userId, user.id)))
        .limit(1);
      if (current?.folderId === removeFolderId) {
        patch.folderId = null;
      }
    }
    await db
      .update(feeds)
      .set(patch)
      .where(and(eq(feeds.id, feedId), eq(feeds.userId, user.id)));
  }

  return greaderOk();
}

// ---------------------------------------------------------------------------
// Tag (folder) mutations — NetNewsWire folder management
// ---------------------------------------------------------------------------

async function handleRenameTag(request: Request, context: Record<string, unknown>): Promise<Response> {
  const user = needUser(context);
  const params = await readGreaderParams(request);
  const badToken = verifyGreaderPostToken(params, user);
  if (badToken) {
    return badToken;
  }

  const source = parseLabelTag(params.get("s"));
  const destination = parseLabelTag(params.get("dest"));
  if (source === null || source === undefined || destination === null || destination === undefined) {
    throw new AppError("Invalid rename-tag parameters", 400);
  }

  const db = await getDb();
  const [folder] = await db
    .select({ id: folders.id })
    .from(folders)
    .where(and(eq(folders.userId, user.id), eq(folders.name, source)))
    .limit(1);
  if (!folder) {
    throw new AppError("Folder not found", 400);
  }

  const [conflict] = await db
    .select({ id: folders.id })
    .from(folders)
    .where(and(eq(folders.userId, user.id), eq(folders.name, destination)))
    .limit(1);
  if (conflict) {
    throw new AppError("Folder already exists", 400);
  }

  await db
    .update(folders)
    .set({ name: destination, updatedAt: new Date() })
    .where(eq(folders.id, folder.id));

  return greaderOk();
}

// Google semantics: remove the folder; feeds keep existing (move to root).
// The house DELETE /folders/:id refuses non-empty folders, so feeds are
// detached first — the greader contract wins here.
async function handleDisableTag(request: Request, context: Record<string, unknown>): Promise<Response> {
  const user = needUser(context);
  const params = await readGreaderParams(request);
  const badToken = verifyGreaderPostToken(params, user);
  if (badToken) {
    return badToken;
  }

  const label = parseLabelTag(params.get("s"));
  if (label === null || label === undefined) {
    throw new AppError("Invalid disable-tag parameters", 400);
  }

  const db = await getDb();
  const [folder] = await db
    .select({ id: folders.id })
    .from(folders)
    .where(and(eq(folders.userId, user.id), eq(folders.name, label)))
    .limit(1);
  if (!folder) {
    return greaderOk();
  }

  await db
    .update(feeds)
    .set({ folderId: null, updatedAt: new Date() })
    .where(and(eq(feeds.folderId, folder.id), eq(feeds.userId, user.id)));
  await db.delete(folders).where(eq(folders.id, folder.id));

  return greaderOk();
}

type RouteContext = {
  request: Request;
  params: Record<string, string>;
  context: Record<string, unknown>;
};

export async function greaderLoaderHandle({ request, params, context }: RouteContext): Promise<never> {
  throw await greaderHandle(async () => dispatch(request, params, context));
}

export async function greaderActionHandle({ request, params, context }: RouteContext): Promise<Response> {
  return greaderHandle(async () => dispatch(request, params, context));
}
