import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));
vi.mock("../services/feed-fetch.js", () => ({ fetchFeedXml: vi.fn() }));
vi.mock("../data/runtime.js", () => ({
  getDataRuntime: vi.fn(async () => ({ queue: { add: vi.fn() } })),
}));

import { action } from "../routes/api/feeds/index.js";
import { getDb } from "../lib/api/db.js";
import { fetchFeedXml } from "../services/feed-fetch.js";

// POST /api/feeds tenancy + duplicate-subscribe contract (audit F014/F043):
// the target folder must belong to the caller, and the (user_id, url)
// unique index race maps to the same 409 as the pre-check.

const FEED_XML = `<?xml version="1.0"?><rss version="2.0"><channel><title>Example Feed</title><link>https://example.com/</link></channel></rss>`;

function thenable(rows: unknown[]) {
  const q: Record<string, unknown> = {
    then: (onFulfilled: (value: unknown) => unknown, onRejected: (reason: unknown) => unknown) =>
      Promise.resolve(rows).then(onFulfilled, onRejected),
  };
  for (const method of ["from", "where", "limit"]) {
    q[method] = () => q;
  }
  return q as never;
}

function postRequest(body: unknown): Request {
  return new Request("http://localhost/api/feeds", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

const context = { user: { id: "u1" } };

beforeEach(() => {
  vi.mocked(getDb).mockReset();
  vi.mocked(fetchFeedXml).mockReset().mockResolvedValue(FEED_XML);
});

describe("POST /api/feeds", () => {
  it("rejects a folderId owned by another user with 404 (before any fetch)", async () => {
    const inserts: unknown[] = [];
    const db = {
      select: () => thenable([]),
      insert: () => ({
        values: (v: unknown) => ({
          returning: async () => {
            inserts.push(v);
            return [];
          },
        }),
      }),
    };
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: postRequest({ url: "https://example.com/feed.xml", folderId: "00000000-0000-0000-0000-00000000000b" }),
      context,
    });

    expect(response.status).toBe(404);
    expect(fetchFeedXml).not.toHaveBeenCalled();
    expect(inserts).toHaveLength(0);
  });

  it("maps a unique-index violation (concurrent subscribe) to 409 Already subscribed", async () => {
    const db = {
      select: () => thenable([]),
      insert: () => ({
        values: () => ({
          returning: async () => {
            const error = new Error("duplicate key value violates unique constraint") as Error & { code?: string };
            error.code = "23505";
            throw error;
          },
        }),
      }),
    };
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: postRequest({ url: "https://example.com/feed.xml" }),
      context,
    });

    expect(response.status).toBe(409);
    const body = (await response.json()) as { error: string };
    expect(body.error).toContain("Already subscribed");
  });
});
