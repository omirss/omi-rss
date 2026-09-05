import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));

import { loader as articleListLoader } from "../routes/api/articles/index.js";
import { loader as articleDetailLoader } from "../routes/api/articles/[articleId].js";
import { loader as feedsListLoader } from "../routes/api/feeds/index.js";
import { loader as feedDetailLoader } from "../routes/api/feeds/[feedId].js";
import { getDb } from "../lib/api/db.js";

// Payload-shape contract tests: article LIST payloads must not carry the
// (up to 256KB) contentExtracted column — GET /api/articles/:id detail
// keeps it; the feeds list must select settings so the structured
// pageStatus reaches the webui.

interface SelectCall {
  fields: unknown;
}

function makeDb(selectResults: unknown[][]) {
  const selectCalls: SelectCall[] = [];
  let selectIndex = 0;
  const query = (rows: unknown[]) => {
    const q: Record<string, unknown> = {
      then: (onFulfilled: (value: unknown) => unknown, onRejected: (reason: unknown) => unknown) =>
        Promise.resolve(rows).then(onFulfilled, onRejected),
    };
    for (const method of ["from", "innerJoin", "leftJoin", "where", "orderBy", "groupBy", "limit", "offset"]) {
      q[method] = () => q;
    }
    return q as never;
  };
  const db = {
    select: (fields?: unknown) => {
      selectCalls.push({ fields });
      const rows = selectResults[Math.min(selectIndex, selectResults.length - 1)] ?? [];
      selectIndex++;
      return query(rows);
    },
  };
  return { db, selectCalls };
}

async function thrownResponse(promise: Promise<unknown>): Promise<Response> {
  try {
    await promise;
  } catch (error) {
    return error as Response;
  }
  throw new Error("expected loader to throw its Response");
}

const context = { user: { id: "u1" } };

beforeEach(() => {
  vi.mocked(getDb).mockReset();
});

describe("article list payload", () => {
  it("omits contentExtracted from both the SQL projection and the JSON body", async () => {
    const { db, selectCalls } = makeDb([
      [{ id: "a1", title: "T", isRead: null, isStarred: null }],
      [{ count: 1 }],
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await thrownResponse(
      articleListLoader({
        request: new Request("http://localhost/api/articles?page=1&limit=20"),
        context,
      }),
    );

    expect(response).toBeInstanceOf(Response);
    const listFields = selectCalls[0].fields as Record<string, unknown>;
    expect(Object.keys(listFields)).not.toContain("contentExtracted");

    const body = (await response.json()) as { articles: Array<Record<string, unknown>>; pagination: { total: number } };
    expect(body.articles).toHaveLength(1);
    expect(body.articles[0]).not.toHaveProperty("contentExtracted");
    expect(body.pagination.total).toBe(1);
  });
});

describe("article detail payload", () => {
  it("keeps contentExtracted in the projection and the JSON body", async () => {
    const { db, selectCalls } = makeDb([
      [{ id: "a1", title: "T", contentExtracted: "<p>full text</p>", isRead: null, isStarred: null }],
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await thrownResponse(
      articleDetailLoader({ params: { articleId: "a1" }, context }),
    );

    expect(response).toBeInstanceOf(Response);
    const detailFields = selectCalls[0].fields as Record<string, unknown>;
    expect(Object.keys(detailFields)).toContain("contentExtracted");

    const body = (await response.json()) as { article: Record<string, unknown> };
    expect(body.article.contentExtracted).toBe("<p>full text</p>");
  });

  it("404s for articles the user does not own", async () => {
    const { db } = makeDb([[]]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await thrownResponse(
      articleDetailLoader({ params: { articleId: "someone-elses" }, context }),
    );
    expect(response.status).toBe(404);
  });
});

describe("feeds list payload", () => {
  it("selects settings so the structured pageStatus is carried through", async () => {
    const { db, selectCalls } = makeDb([
      [{ id: "f1", title: "Page feed", settings: { pageStatus: "selector-miss" }, unreadCount: 2 }],
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await thrownResponse(feedsListLoader({ context }));

    expect(response).toBeInstanceOf(Response);
    const feedFields = selectCalls[0].fields as Record<string, unknown>;
    expect(Object.keys(feedFields)).toContain("settings");

    const body = (await response.json()) as { feeds: Array<Record<string, unknown>> };
    expect(body.feeds[0].settings).toEqual({ pageStatus: "selector-miss" });
  });

  it("omits httpHeaders from the projection (owner cookies never ride the list)", async () => {
    const { db, selectCalls } = makeDb([
      [{ id: "f1", title: "Feed", unreadCount: 0 }],
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await thrownResponse(feedsListLoader({ context }));

    const feedFields = selectCalls[0].fields as Record<string, unknown>;
    expect(Object.keys(feedFields)).not.toContain("httpHeaders");

    const body = (await response.json()) as { feeds: Array<Record<string, unknown>> };
    expect(body.feeds[0]).not.toHaveProperty("httpHeaders");
  });
});

describe("feed detail payload", () => {
  it("includes the owner's httpHeaders (detail is owner-only)", async () => {
    const { db } = makeDb([
      [{ id: "f1", userId: "u1", fullTextEnabled: false, httpHeaders: { cookie: "s=t" } }],
      [{ totalArticles: 1, unreadArticles: 1 }],
    ]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await thrownResponse(
      feedDetailLoader({ params: { feedId: "f1" }, context }),
    );

    expect(response).toBeInstanceOf(Response);
    const body = (await response.json()) as { feed: Record<string, unknown> };
    expect(body.feed.httpHeaders).toEqual({ cookie: "s=t" });
  });
});
