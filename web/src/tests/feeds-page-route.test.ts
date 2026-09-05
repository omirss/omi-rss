import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));
vi.mock("../data/runtime.js", () => ({
  getDataRuntime: vi.fn(async () => ({ queue: { add: vi.fn() } })),
}));

import { action, middleware } from "../routes/api/feeds/page.js";
import { getDb } from "../lib/api/db.js";
import { getDataRuntime } from "../data/runtime.js";

// Route-handler tests for POST /api/feeds/page with a fake db and stubbed
// outbound fetch — no network, no database. The pageUrl is a literal public
// IP so assertSafeFeedUrl needs no DNS.

const PAGE_URL = "https://93.184.216.34/blog";
const SELECTOR = "article.post";
const PAGE_HTML = `<!doctype html><html><head><title>Fixture Blog</title></head><body>
  <article class="post"><h2><a href="/posts/one">First</a></h2></article>
</body></html>`;

function pageFeedBody(overrides: Record<string, unknown> = {}): Request {
  return new Request("http://localhost/api/feeds/page", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ pageUrl: PAGE_URL, pageSelector: SELECTOR, ...overrides }),
  });
}

interface Call {
  selectFields: unknown;
}

function fakeDb(existingFeedRows: unknown[], insertRows: unknown[]) {
  const calls: Call[] = [];
  const query = (rows: unknown[]) => {
    const q: Record<string, unknown> = {
      then: (onFulfilled: (value: unknown) => unknown, onRejected: (reason: unknown) => unknown) =>
        Promise.resolve(rows).then(onFulfilled, onRejected),
    };
    for (const method of ["from", "where", "limit"]) {
      q[method] = () => q;
    }
    return q as never;
  };
  const db = {
    select: (fields?: unknown) => {
      calls.push({ selectFields: fields });
      return query(existingFeedRows);
    },
    insert: () => ({
      values: () => ({
        returning: async () => insertRows,
      }),
    }),
  };
  return { db, calls };
}

beforeEach(() => {
  vi.mocked(getDb).mockReset();
  vi.mocked(getDataRuntime).mockClear();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("POST /api/feeds/page handler", () => {
  it("rejects unauthenticated requests with 401 (middleware)", async () => {
    const response = await middleware(
      new Request("http://localhost/api/feeds/page", { method: "POST" }),
      {},
      async () => new Response("next"),
    );
    expect(response.status).toBe(401);
  });

  it("returns 409 when the user already subscribes to the page feed", async () => {
    const { db } = fakeDb([{ id: "existing-feed" }], []);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({ request: pageFeedBody(), context: { user: { id: "u1" } } });

    expect(response.status).toBe(409);
    const body = (await response.json()) as { error: string };
    expect(body.error).toContain("Already subscribed");
  });

  it("returns 400 when the selector matches 0 elements (selector miss)", async () => {
    const { db } = fakeDb([], []);
    vi.mocked(getDb).mockResolvedValue(db as never);
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        new Response('<html><body><div class="redesigned">no matches here</div></body></html>', {
          status: 200,
          headers: { "content-type": "text/html" },
        }),
      ),
    );

    const response = await action({
      request: pageFeedBody({ pageSelector: "article.post" }),
      context: { user: { id: "u1" } },
    });

    expect(response.status).toBe(400);
    const body = (await response.json()) as { error: string };
    expect(body.error).toContain("Selector matched 0 elements");
  });

  it("returns 201 and enqueues the first update when verification passes", async () => {
    const insertedFeed = {
      id: "feed-1",
      url: PAGE_URL,
      title: "Fixture Blog",
      sourceType: "page",
      pageUrl: PAGE_URL,
      pageSelector: SELECTOR,
      settings: {},
    };
    const { db } = fakeDb([], [insertedFeed]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const fetchImpl = vi.fn(async () =>
      new Response(PAGE_HTML, { status: 200, headers: { "content-type": "text/html" } }),
    );
    vi.stubGlobal("fetch", fetchImpl);

    const response = await action({ request: pageFeedBody(), context: { user: { id: "u1" } } });

    expect(response.status).toBe(201);
    const body = (await response.json()) as { feed: { id: string; sourceType: string } };
    expect(body.feed.id).toBe("feed-1");
    expect(body.feed.sourceType).toBe("page");
    expect(fetchImpl).toHaveBeenCalled();
    const runtime = await vi.mocked(getDataRuntime).mock.results[0]?.value;
    expect((runtime as { queue: { add: ReturnType<typeof vi.fn> } }).queue.add).toHaveBeenCalledWith(
      "feed.update-single",
      { feedId: "feed-1" },
    );
  });

  it("returns 400 for unsafe pageUrls (SSRF surface)", async () => {
    const { db } = fakeDb([], []);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: pageFeedBody({ pageUrl: "http://127.0.0.1:6380" }),
      context: { user: { id: "u1" } },
    });

    expect(response.status).toBe(400);
  });
});
