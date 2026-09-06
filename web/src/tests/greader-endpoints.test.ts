import { describe, it, expect, beforeAll, vi, beforeEach } from "vitest";
import jwt from "jsonwebtoken";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));
vi.mock("../lib/greader/limit.js", () => ({ consumeGreaderRateLimit: vi.fn() }));
vi.mock("../services/feed-fetch.js", () => ({ fetchFeedXml: vi.fn() }));
vi.mock("../data/runtime.js", () => ({ getDataRuntime: vi.fn() }));

import { action, loader } from "../routes/api/greader/[...path].js";
import { getDb } from "../lib/api/db.js";
import { fetchFeedXml } from "../services/feed-fetch.js";
import { getDataRuntime } from "../data/runtime.js";
import { signGreaderPostToken } from "../lib/api/tokens.js";

// Endpoint contracts against a fake drizzle db (thenable query objects,
// house pattern from feeds-update-route.test.ts / payload-shape.test.ts):
// every endpoint gets a happy path plus its primary error path.

beforeAll(() => {
  process.env.JWT_SECRET = "test-secret";
});

const USER = {
  id: "u1",
  email: "alice@example.com",
  username: "alice",
  role: "user",
  tokenVersion: 0,
  createdAt: new Date("2026-01-01T00:00:00Z"),
};

const context = { user: USER };

function makeDb(selectResults: unknown[][]) {
  const inserts: Array<Record<string, unknown>> = [];
  const updates: Array<Record<string, unknown>> = [];
  const deletes: Array<Record<string, unknown>> = [];
  let selectIndex = 0;

  const query = (rows: unknown[], label: string) => {
    let limit = Infinity;
    const q: Record<string, unknown> = {
      then: (res: (v: unknown) => unknown, rej: (r: unknown) => unknown) =>
        Promise.resolve(limit === Infinity ? rows : rows.slice(0, limit)).then(res, rej),
      __label: label,
    };
    for (const method of ["from", "innerJoin", "leftJoin", "where", "orderBy", "groupBy", "offset"]) {
      q[method] = () => q;
    }
    q.limit = (n: number) => {
      limit = n;
      return q;
    };
    return q;
  };

  const db = {
    select: () => {
      const rows = selectResults[Math.min(selectIndex, selectResults.length - 1)] ?? [];
      selectIndex++;
      return query(rows, `select${selectIndex}`);
    },
    insert: () => ({
      select: (inner: unknown) => ({
        onConflictDoUpdate: (conflict: Record<string, unknown>) => {
          inserts.push({ kind: "select", inner, conflict });
          return Promise.resolve([]);
        },
      }),
      values: (values: Record<string, unknown>) => ({
        returning: async () => {
          inserts.push({ kind: "values", values });
          return selectResults[Math.min(selectIndex, selectResults.length - 1)] ?? [];
        },
      }),
    }),
    update: () => ({
      set: (patch: Record<string, unknown>) => ({
        where: () => {
          updates.push(patch);
          return Promise.resolve([]);
        },
        returning: async () => {
          updates.push(patch);
          return [];
        },
      }),
    }),
    delete: () => ({
      where: (condition: unknown) => {
        deletes.push({ condition });
        return Promise.resolve();
      },
    }),
  };
  return { db, inserts, updates, deletes };
}

async function thrownResponse(promise: Promise<unknown>): Promise<Response> {
  try {
    await promise;
  } catch (error) {
    return error as Response;
  }
  throw new Error("expected loader to throw its Response");
}

function get(path: string): { request: Request; params: { path: string }; context: unknown } {
  return {
    request: new Request(`http://localhost/api/greader/${path}`),
    params: { path: path.split("?")[0] },
    context,
  };
}

function post(path: string, body: string): { request: Request; params: { path: string }; context: unknown } {
  return {
    request: new Request(`http://localhost/api/greader/${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    }),
    params: { path },
    context,
  };
}

function validT(): string {
  return signGreaderPostToken("u1", 0);
}

const ITEM_ROW = {
  hex16: "fb115bd6d34a8e9f",
  id: "fb115bd6d34a8e9f-0000-4000-8000-000000000000",
  rankUsec: "1750000000123456",
  title: "A1 title",
  url: "https://example.com/a1",
  author: "Jane Doe",
  content: "<p>hello</p>",
  summary: null,
  publishedAt: new Date("2026-08-01T12:00:00Z"),
  enclosures: [{ url: "https://example.com/img.jpg", type: "image/jpeg" }],
  isRead: false,
  isStarred: true,
  feedUrl: "https://example.com/a.xml",
  feedTitle: "Feed A",
  feedCustomTitle: null,
  feedSiteUrl: "https://example.com/",
  folderName: "Tech",
};

const FEED_XML = `<?xml version="1.0"?><rss version="2.0"><channel><title>Example Feed</title><link>https://example.com/</link></channel></rss>`;

beforeEach(() => {
  vi.mocked(getDb).mockReset();
  vi.mocked(fetchFeedXml).mockReset().mockResolvedValue(FEED_XML);
  vi.mocked(getDataRuntime).mockReset().mockResolvedValue({
    queue: { add: vi.fn(async () => {}) },
  } as never);
});

describe("user-info", () => {
  it("returns the superset shape", async () => {
    const response = await thrownResponse(loader(get("reader/api/0/user-info") as never) as never);
    expect(response.status).toBe(200);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.userId).toBe("u1");
    expect(body.userName).toBe("alice");
    expect(body.userProfileId).toBe("u1");
    expect(body.userEmail).toBe("alice@example.com");
    expect(body.isBloggerUser).toBe(false);
    expect(body.isMultiLoginEnabled).toBe(false);
    expect(body.signupTimeSec).toBe(Math.floor(USER.createdAt.getTime() / 1000));
  });
});

describe("token", () => {
  it("returns a newline-terminated 30-minute post token", async () => {
    const response = await thrownResponse(loader(get("reader/api/0/token") as never) as never);
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toContain("text/plain");
    const text = await response.text();
    expect(text.endsWith("\n")).toBe(true);
    const payload = jwt.decode(text.trim()) as jwt.JwtPayload;
    expect(payload.type).toBe("greader-post");
    expect((payload.exp! - payload.iat!) / 60).toBe(30);
  });
});

describe("subscription/list", () => {
  it("emits feed/<url> ids with label categories", async () => {
    const { db } = makeDb([
      [
        { url: "https://example.com/a.xml", title: "Feed A", customTitle: null, siteUrl: "https://example.com/", favicon: null, folderName: "Tech" },
        { url: "https://example.org/b.xml", title: "Feed B", customTitle: "B!", siteUrl: null, favicon: null, folderName: null },
      ],
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await thrownResponse(loader(get("reader/api/0/subscription/list") as never) as never);
    const body = (await response.json()) as { subscriptions: Array<Record<string, unknown>> };
    expect(body.subscriptions).toHaveLength(2);
    const [a, b] = body.subscriptions;
    expect(a.id).toBe("feed/https://example.com/a.xml");
    expect(a.title).toBe("Feed A");
    expect(a.url).toBe("https://example.com/a.xml");
    expect(a.htmlUrl).toBe("https://example.com/");
    expect(a.categories).toEqual([{ id: "user/-/label/Tech", label: "Tech" }]);
    expect(b.title).toBe("B!");
    expect(b.categories).toEqual([]);
  });
});

describe("tag/list", () => {
  it("includes starred, reading-list and one entry per folder", async () => {
    const { db } = makeDb([[{ id: "f1", name: "Tech" }, { id: "f2", name: "News" }]]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await thrownResponse(loader(get("reader/api/0/tag/list") as never) as never);
    const body = (await response.json()) as { tags: Array<{ id: string }> };
    const ids = body.tags.map((t) => t.id);
    expect(ids).toContain("user/-/state/com.google/starred");
    expect(ids).toContain("user/-/state/com.google/reading-list");
    expect(ids).toContain("user/-/label/Tech");
    expect(ids).toContain("user/-/label/News");
  });
});

describe("unread-count", () => {
  it("aggregates per feed, per folder and the reading-list total", async () => {
    const { db } = makeDb([
      [
        { url: "https://example.com/a.xml", folderId: "F1", folderName: "Tech", unread: 3, newestUnread: "1700000000000000", newestAny: "1700000000000000" },
        { url: "https://example.org/b.xml", folderId: "F1", folderName: "Tech", unread: 1, newestUnread: "1700000001000000", newestAny: "1700000001000000" },
      ],
      [{ id: "F1", name: "Tech" }, { id: "F2", name: "Empty" }],
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await thrownResponse(loader(get("reader/api/0/unread-count") as never) as never);
    const body = (await response.json()) as {
      max: number;
      unreadcounts: Array<{ id: string; count: number; newestItemTimestampUsec: string }>;
    };
    expect(body.max).toBe(1000);
    const byId = new Map(body.unreadcounts.map((c) => [c.id, c]));
    expect(byId.get("feed/https://example.com/a.xml")).toMatchObject({ count: 3, newestItemTimestampUsec: "1700000000000000" });
    expect(byId.get("user/-/label/Tech")).toMatchObject({ count: 4, newestItemTimestampUsec: "1700000001000000" });
    expect(byId.get("user/-/label/Empty")).toMatchObject({ count: 0, newestItemTimestampUsec: "0" });
    expect(byId.get("user/-/state/com.google/reading-list")).toMatchObject({ count: 4 });
  });
});

describe("stream/items/ids", () => {
  it("returns short signed decimal ids, newest first, no continuation when exhausted", async () => {
    const rows = [
      { hex16: "fb115bd6d34a8e9f", id: "r1", rankUsec: "1750000000123456", feedUrl: "https://example.com/a.xml" },
      { hex16: "000088960000047a", id: "r2", rankUsec: "1750000000000000", feedUrl: "https://example.com/a.xml" },
    ];
    const { db } = makeDb([rows]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await thrownResponse(
      loader(
        get(
          "reader/api/0/stream/items/ids?output=json&s=user/-/state/com.google/reading-list&xt=user/-/state/com.google/read&n=1000"
        ) as never
      ) as never
    );
    const body = (await response.json()) as { itemRefs: Array<{ id: string; timestampUsec: string }> };
    expect(body.itemRefs.map((r) => r.id)).toEqual(["-355401917359550817", "150177826473082"]);
    expect(body.itemRefs[0].timestampUsec).toBe("1750000000123456");
    expect(body).not.toHaveProperty("continuation");
  });

  it("returns an empty itemRefs page for an unknown feed", async () => {
    const { db } = makeDb([[]]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const response = await thrownResponse(
      loader(get("reader/api/0/stream/items/ids?s=feed/https://missing.example/x.xml") as never) as never
    );
    const body = (await response.json()) as { itemRefs: unknown[] };
    expect(body.itemRefs).toEqual([]);
  });

  it("400s on a malformed stream id", async () => {
    const response = await thrownResponse(loader(get("reader/api/0/stream/items/ids?s=zzz") as never) as never);
    expect(response.status).toBe(400);
  });

  it("400s on a tampered continuation", async () => {
    const response = await thrownResponse(
      loader(get("reader/api/0/stream/items/ids?s=user/-/state/com.google/reading-list&c=bogus.sig") as never) as never
    );
    expect(response.status).toBe(400);
  });
});

describe("stream/items/contents", () => {
  it("accepts long and short forms, returns long-form items", async () => {
    const { db } = makeDb([[ITEM_ROW]]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const longForm = "tag:google.com,2005:reader/item/fb115bd6d34a8e9f";
    const first = await action(
      post("reader/api/0/stream/items/contents", `output=json&i=${encodeURIComponent(longForm)}`) as never
    );
    const short = await action(
      post("reader/api/0/stream/items/contents", `i=-355401917359550817`) as never
    );

    for (const response of [first, short]) {
      expect(response.status).toBe(200);
      const body = (await response.json()) as Record<string, unknown>;
      expect(body.id).toBe("user/-/state/com.google/reading-list");
      expect(typeof body.updated).toBe("number");
      const items = body.items as Array<Record<string, unknown>>;
      expect(items).toHaveLength(1);
      const item = items[0];
      expect(item.id).toBe(longForm);
      expect(item.categories).toContain("user/-/state/com.google/reading-list");
      expect(item.categories).toContain("user/-/label/Tech");
      expect(item.categories).toContain("user/-/state/com.google/starred");
      expect(item.categories).not.toContain("user/-/state/com.google/read");
      expect(item.origin).toEqual({
        streamId: "feed/https://example.com/a.xml",
        title: "Feed A",
        htmlUrl: "https://example.com/",
      });
      expect((item.summary as { content: string }).content).toBe("<p>hello</p>");
      expect(item.published).toBe(Math.floor(new Date("2026-08-01T12:00:00Z").getTime() / 1000));
      expect(item.crawlTimeMsec).toBe("1750000000123");
      expect(item.timestampUsec).toBe("1750000000123456");
      expect(item.enclosure).toEqual([{ href: "https://example.com/img.jpg", type: "image/jpeg" }]);
    }
  });

  it("400s without i and on malformed i", async () => {
    const noIds = await action(post("reader/api/0/stream/items/contents", "output=json") as never);
    expect(noIds.status).toBe(400);
    const bad = await action(post("reader/api/0/stream/items/contents", "i=not-an-id") as never);
    expect(bad.status).toBe(400);
  });

  it("omits unknown ids instead of 404ing", async () => {
    const { db } = makeDb([[]]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const response = await action(post("reader/api/0/stream/items/contents", "i=-355401917359550817") as never);
    expect(response.status).toBe(200);
    const body = (await response.json()) as { items: unknown[] };
    expect(body.items).toEqual([]);
  });
});

describe("stream/contents", () => {
  it("serves the bare form as reading-list", async () => {
    const { db } = makeDb([[ITEM_ROW]]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const response = await thrownResponse(loader(get("reader/api/0/stream/contents?output=json&n=50") as never) as never);
    expect(response.status).toBe(200);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.id).toBe("user/-/state/com.google/reading-list");
    expect(typeof body.updated).toBe("number");
    expect((body.items as unknown[]).length).toBe(1);
  });

  it("serves the query form with a byte-identical feed id", async () => {
    const { db } = makeDb([
      [{ id: "feed-uuid-1", url: "https://example.com/a.xml" }],
      [ITEM_ROW],
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const response = await thrownResponse(
      loader(get("reader/api/0/stream/contents?s=feed/https://example.com/a.xml&output=json&n=2") as never) as never
    );
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.id).toBe("feed/https://example.com/a.xml");
  });

  it("repairs the path form's collapsed scheme slashes and echoes the canonical url", async () => {
    const { db } = makeDb([
      [{ id: "feed-uuid-1", url: "https://example.com/a.xml" }],
      [ITEM_ROW],
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    // The router drops empty path segments, so feed/https://x arrives as
    // feed/https:/x in the splat.
    const response = await thrownResponse(
      loader(
        get(
          "reader/api/0/stream/contents/feed/https:/example.com/a.xml?output=json&n=50"
        ) as never
      ) as never
    );
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.id).toBe("feed/https://example.com/a.xml");
    expect((body.items as unknown[]).length).toBe(1);
  });

  it("serves label path and query forms", async () => {
    const { db } = makeDb([
      [{ id: "F1", name: "Tech" }],
      [ITEM_ROW],
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const response = await thrownResponse(
      loader(get("reader/api/0/stream/contents/user/-/label/Tech?output=json") as never) as never
    );
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.id).toBe("user/-/label/Tech");
  });

  it("decodes a percent-encoded splat (dev runtime hands it encoded)", async () => {
    const { db } = makeDb([
      [{ id: "feed-uuid-1", url: "https://example.com/a.xml" }],
      [ITEM_ROW],
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const response = await thrownResponse(
      loader({
        request: new Request("http://localhost/api/greader/reader/api/0/stream/contents/feed%2Fhttps%3A%2F%2Fexample.com%2Fa.xml?output=json"),
        params: { path: "reader/api/0/stream/contents/feed%2Fhttps%3A%2F%2Fexample.com%2Fa.xml" },
        context,
      }) as never
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.id).toBe("feed/https://example.com/a.xml");
    expect((body.items as unknown[]).length).toBe(1);
  });
});

describe("edit-tag", () => {
  it("401 + X-Reader-Google-Bad-Token on garbage T", async () => {
    const response = await action(
      post("reader/api/0/edit-tag", `T=garbage&i=-355401917359550817&a=user/-/state/com.google/read`) as never
    );
    expect(response.status).toBe(401);
    expect(response.headers.get("X-Reader-Google-Bad-Token")).toBe("true");
  });

  it("tolerates a missing T (FeedMe)", async () => {
    const { db, inserts } = makeDb([[{ id: "a-uuid-1" }]]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const response = await action(
      post("reader/api/0/edit-tag", "i=-355401917359550817&a=user/-/state/com.google/read") as never
    );
    expect(await response.text()).toBe("OK");
    expect(inserts).toHaveLength(1);
  });

  it("applies read+starred adds and removes in one call", async () => {
    const { db, inserts } = makeDb([[{ id: "a-uuid-1" }]]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const response = await action(
      post(
        "reader/api/0/edit-tag",
        `T=${encodeURIComponent(validT())}&i=-355401917359550817&r=user/-/state/com.google/read&a=user/-/state/com.google/starred`
      ) as never
    );
    expect(await response.text()).toBe("OK");
    expect(inserts).toHaveLength(1);
  });

  it("returns OK without writes for unknown ids or no-op-only tags", async () => {
    const empty = makeDb([[{ id: "a-uuid-1" }]]);
    vi.mocked(getDb).mockResolvedValue(empty.db as never);
    const noop = await action(
      post("reader/api/0/edit-tag", `T=${encodeURIComponent(validT())}&i=-355401917359550817&a=user/-/state/com.google/broadcast`) as never
    );
    expect(await noop.text()).toBe("OK");
    expect(empty.inserts).toHaveLength(0);

    const missing = makeDb([[]]);
    vi.mocked(getDb).mockResolvedValue(missing.db as never);
    const gone = await action(
      post("reader/api/0/edit-tag", `T=${encodeURIComponent(validT())}&i=-355401917359550817&a=user/-/state/com.google/read`) as never
    );
    expect(await gone.text()).toBe("OK");
    expect(missing.inserts).toHaveLength(0);
  });

  it("400s on missing i, malformed i and invalid tags", async () => {
    const noIds = await action(post("reader/api/0/edit-tag", `T=${encodeURIComponent(validT())}`) as never);
    expect(noIds.status).toBe(400);
    const badId = await action(post("reader/api/0/edit-tag", `T=${encodeURIComponent(validT())}&i=zzz`) as never);
    expect(badId.status).toBe(400);
    const badTag = await action(
      post("reader/api/0/edit-tag", `T=${encodeURIComponent(validT())}&i=-355401917359550817&a=zzz`) as never
    );
    expect(badTag.status).toBe(400);
  });
});

describe("mark-all-as-read", () => {
  it("marks the reading-list with and without ts", async () => {
    const { db, inserts } = makeDb([[]]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const noTs = await action(
      post("reader/api/0/mark-all-as-read", `T=${encodeURIComponent(validT())}&s=user/-/state/com.google/reading-list`) as never
    );
    expect(await noTs.text()).toBe("OK");
    expect(inserts).toHaveLength(1);

    const withTs = await action(
      post(
        "reader/api/0/mark-all-as-read",
        `T=${encodeURIComponent(validT())}&s=user/-/state/com.google/reading-list&ts=1750000000000000`
      ) as never
    );
    expect(await withTs.text()).toBe("OK");
    expect(inserts).toHaveLength(2);
  });

  it("scopes to a feed stream id and tolerates nanosecond ts", async () => {
    const { db, inserts } = makeDb([
      [{ id: "feed-uuid-1", url: "https://example.com/a.xml" }],
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const response = await action(
      post(
        "reader/api/0/mark-all-as-read",
        `T=${encodeURIComponent(validT())}&s=feed/https://example.com/a.xml&ts=1750000000000000000`
      ) as never
    );
    expect(await response.text()).toBe("OK");
    expect(inserts).toHaveLength(1);
  });

  it("400s without s and with a bad T", async () => {
    const missing = await action(post("reader/api/0/mark-all-as-read", `T=${encodeURIComponent(validT())}`) as never);
    expect(missing.status).toBe(400);
    const badT = await action(post("reader/api/0/mark-all-as-read", "T=zzz&s=user/-/state/com.google/reading-list") as never);
    expect(badT.status).toBe(401);
  });
});

describe("subscription/quickadd", () => {
  it("returns numResults 0 for non-http input", async () => {
    const response = await action(
      post("reader/api/0/subscription/quickadd", `T=${encodeURIComponent(validT())}&quickadd=not-a-url`) as never
    );
    const body = (await response.json()) as { numResults: number; error: string };
    expect(body.numResults).toBe(0);
  });

  it("subscribes through the SSRF-guarded fetch and enqueues the backfill", async () => {
    const { db, inserts } = makeDb([
      [], // dup check: not subscribed
      [{ id: "feed-new", url: "https://example.net/c.xml", title: "Example Feed" }], // insert returning
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action(
      post("reader/api/0/subscription/quickadd", `T=${encodeURIComponent(validT())}&quickadd=https://example.net/c.xml`) as never
    );
    const body = (await response.json()) as { numResults: number; streamId: string; streamName: string };
    expect(body.numResults).toBe(1);
    expect(body.streamId).toBe("feed/https://example.net/c.xml");
    expect(body.streamName).toBe("Example Feed");
    expect(fetchFeedXml).toHaveBeenCalledWith("https://example.net/c.xml");
    expect(inserts).toHaveLength(1);
  });

  it("reports already-subscribed and fetch failures as numResults 0", async () => {
    const dup = makeDb([
      [{ id: "feed-new", url: "https://example.net/c.xml" }], // dup check hit
      [{ url: "https://example.net/c.xml", title: "x" }], // quickadd re-check
    ]);
    vi.mocked(getDb).mockResolvedValue(dup.db as never);
    const dupResponse = await action(
      post("reader/api/0/subscription/quickadd", `T=${encodeURIComponent(validT())}&quickadd=feed/https://example.net/c.xml`) as never
    );
    const dupBody = (await dupResponse.json()) as { numResults: number; error: string };
    expect(dupBody.numResults).toBe(0);
    expect(dupBody.error).toBe("already subscribed");
    expect(fetchFeedXml).not.toHaveBeenCalled();

    const fail = makeDb([[], []]);
    vi.mocked(getDb).mockResolvedValue(fail.db as never);
    vi.mocked(fetchFeedXml).mockRejectedValueOnce(new Error("blocked"));
    const failResponse = await action(
      post("reader/api/0/subscription/quickadd", `T=${encodeURIComponent(validT())}&quickadd=https://blocked.example/x.xml`) as never
    );
    const failBody = (await failResponse.json()) as { numResults: number; error: string };
    expect(failBody.numResults).toBe(0);
    expect(failBody.error).toBe("unable to fetch or parse feed");
  });
});

describe("subscription/edit", () => {
  it("renames and moves on ac=edit, accepting feed/<uuid> too", async () => {
    const { db, updates } = makeDb([
      [{ id: "folder-tech" }], // resolveOrCreateFolder(Tech) runs first
      [{ id: "feed-uuid-1", url: "https://example.net/c.xml" }], // resolve s=feed/<url>
      [{ id: "folder-tech" }], // remove-label folder lookup for call 2
      [{ id: "feed-uuid-1", url: "https://example.net/c.xml" }], // resolve s=feed/<uuid>
      [{ folderId: "folder-tech" }], // current folder for r=
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action(
      post(
        "reader/api/0/subscription/edit",
        `T=${encodeURIComponent(validT())}&ac=edit&s=feed/https://example.net/c.xml&t=FeedC&a=user/-/label/Tech`
      ) as never
    );
    expect(await response.text()).toBe("OK");
    expect(updates[0]).toMatchObject({ customTitle: "FeedC", folderId: "folder-tech" });

    const remove = await action(
      post(
        "reader/api/0/subscription/edit",
        `T=${encodeURIComponent(validT())}&ac=edit&s=feed/feed-uuid-1&r=user/-/label/Tech`
      ) as never
    );
    expect(await remove.text()).toBe("OK");
    expect(updates[1]).toMatchObject({ folderId: null });
  });

  it("unsubscribes on ac=unsubscribe", async () => {
    const { db, deletes } = makeDb([
      [{ id: "feed-uuid-1", url: "https://example.net/c.xml" }],
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const response = await action(
      post(
        "reader/api/0/subscription/edit",
        `T=${encodeURIComponent(validT())}&ac=unsubscribe&s=feed/https://example.net/c.xml`
      ) as never
    );
    expect(await response.text()).toBe("OK");
    expect(deletes).toHaveLength(1);
  });

  it("400s on invalid ac, missing s and unknown feeds for edit", async () => {
    const badAc = await action(post("reader/api/0/subscription/edit", `T=${encodeURIComponent(validT())}&ac=zzz&s=feed/x`) as never);
    expect(badAc.status).toBe(400);
    const noS = await action(post("reader/api/0/subscription/edit", `T=${encodeURIComponent(validT())}&ac=edit`) as never);
    expect(noS.status).toBe(400);

    const { db } = makeDb([[]]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const unknown = await action(
      post("reader/api/0/subscription/edit", `T=${encodeURIComponent(validT())}&ac=edit&s=feed/https://missing.example/x.xml`) as never
    );
    expect(unknown.status).toBe(400);
  });
});

describe("rename-tag / disable-tag", () => {
  it("renames a folder label", async () => {
    const { db, updates } = makeDb([
      [{ id: "F1" }], // source folder
      [], // destination conflict check
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const response = await action(
      post(
        "reader/api/0/rename-tag",
        `T=${encodeURIComponent(validT())}&s=user/-/label/Tech&dest=user/-/label/News`
      ) as never
    );
    expect(await response.text()).toBe("OK");
    expect(updates[0]).toMatchObject({ name: "News" });
  });

  it("400s rename on missing folder or name conflict", async () => {
    const missing = makeDb([[]]);
    vi.mocked(getDb).mockResolvedValue(missing.db as never);
    const response = await action(
      post("reader/api/0/rename-tag", `T=${encodeURIComponent(validT())}&s=user/-/label/Nope&dest=user/-/label/New`) as never
    );
    expect(response.status).toBe(400);

    const conflict = makeDb([[{ id: "F1" }], [{ id: "F2" }]]);
    vi.mocked(getDb).mockResolvedValue(conflict.db as never);
    const conflicting = await action(
      post("reader/api/0/rename-tag", `T=${encodeURIComponent(validT())}&s=user/-/label/Tech&dest=user/-/label/News`) as never
    );
    expect(conflicting.status).toBe(400);
  });

  it("disable-tag detaches feeds to root then deletes the folder; idempotent when missing", async () => {
    const { db, updates, deletes } = makeDb([[{ id: "F1" }]]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const response = await action(
      post("reader/api/0/disable-tag", `T=${encodeURIComponent(validT())}&s=user/-/label/Tech`) as never
    );
    expect(await response.text()).toBe("OK");
    expect(updates[0]).toMatchObject({ folderId: null });
    expect(deletes).toHaveLength(1);

    const missing = makeDb([[]]);
    vi.mocked(getDb).mockResolvedValue(missing.db as never);
    const idempotent = await action(
      post("reader/api/0/disable-tag", `T=${encodeURIComponent(validT())}&s=user/-/label/Gone`) as never
    );
    expect(await idempotent.text()).toBe("OK");
    expect(missing.deletes).toHaveLength(0);
  });
});

describe("unknown greader endpoints", () => {
  it("404s the deliberately-unimplemented set", async () => {
    for (const path of [
      "reader/api/0/preference/list",
      "reader/api/0/friend/list",
      "reader/api/0/search/items/ids",
      "reader/api/0/subscription/export",
      "something/else",
    ]) {
      const response = await thrownResponse(loader(get(path) as never) as never);
      expect(response.status).toBe(404);
    }
  });
});
