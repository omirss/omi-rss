import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));

import { action } from "../routes/api/feeds/[feedId].js";
import { getDb } from "../lib/api/db.js";

// PUT /api/feeds/:id contract tests: fullTextEnabled is an rss-feed-only
// toggle — page feeds extract by construction and get a 400.

function putRequest(body: unknown): Request {
  return new Request("http://localhost/api/feeds/f1", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

function fakeDb(existingFeed: unknown[], updatedRows: unknown[]) {
  const updates: Array<Record<string, unknown>> = [];
  const selectQuery = (rows: unknown[]) => {
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
    select: () => selectQuery(existingFeed),
    update: () => ({
      set: (patch: Record<string, unknown>) => ({
        where: () => ({
          returning: async () => {
            updates.push(patch);
            return updatedRows;
          },
        }),
      }),
    }),
    delete: () => ({ where: async () => undefined }),
  };
  return { db, updates };
}

const context = { user: { id: "u1" } };

beforeEach(() => {
  vi.mocked(getDb).mockReset();
});

describe("PUT /api/feeds/:id", () => {
  it("returns 400 when fullTextEnabled is set on a page feed", async () => {
    const { db } = fakeDb([{ id: "f1", userId: "u1", sourceType: "page" }], []);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: putRequest({ fullTextEnabled: true }),
      params: { feedId: "f1" },
      context,
    });

    expect(response.status).toBe(400);
    const body = (await response.json()) as { error: string };
    expect(body.error).toContain("fullTextEnabled");
  });

  it("rejects the key even when false on a page feed (presence is the error)", async () => {
    const { db } = fakeDb([{ id: "f1", userId: "u1", sourceType: "page" }], []);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: putRequest({ fullTextEnabled: false }),
      params: { feedId: "f1" },
      context,
    });

    expect(response.status).toBe(400);
  });

  it("accepts fullTextEnabled on rss feeds", async () => {
    const updated = { id: "f1", sourceType: "rss", fullTextEnabled: true, settings: { keep: 1 } };
    const { db, updates } = fakeDb([{ id: "f1", userId: "u1", sourceType: "rss" }], [updated]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: putRequest({ fullTextEnabled: true }),
      params: { feedId: "f1" },
      context,
    });

    expect(response.status).toBe(200);
    const body = (await response.json()) as { feed: { fullTextEnabled: boolean; settings: unknown } };
    expect(body.feed.fullTextEnabled).toBe(true);
    expect(body.feed.settings).toEqual({ keep: 1 });
    expect(updates).toHaveLength(1);
  });

  it("returns 404 for unknown feeds", async () => {
    const { db } = fakeDb([], []);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: putRequest({ isActive: false }),
      params: { feedId: "missing" },
      context,
    });

    expect(response.status).toBe(404);
  });

  it("accepts allowlisted httpHeaders and persists them", async () => {
    const updated = { id: "f1", sourceType: "rss", httpHeaders: { cookie: "s=t" } };
    const { db, updates } = fakeDb([{ id: "f1", userId: "u1", sourceType: "rss" }], [updated]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: putRequest({ httpHeaders: { Cookie: "s=t", "X-Custom": "v" } }),
      params: { feedId: "f1" },
      context,
    });

    expect(response.status).toBe(200);
    expect(updates).toHaveLength(1);
    expect(updates[0].httpHeaders).toEqual({ cookie: "s=t", "x-custom": "v" });
  });

  it("rejects forbidden httpHeaders names (Host, Content-Length) with 400", async () => {
    const { db, updates } = fakeDb([{ id: "f1", userId: "u1", sourceType: "rss" }], []);
    vi.mocked(getDb).mockResolvedValue(db as never);

    for (const [name, value] of [["Host", "evil.example"], ["Content-Length", "999"], ["Connection", "close"]] as Array<[string, string]>) {
      const response = await action({
        request: putRequest({ httpHeaders: { [name]: value } }),
        params: { feedId: "f1" },
        context,
      });
      expect(response.status).toBe(400);
      const body = (await response.json()) as { error: string };
      expect(body.error).toContain(name);
    }
    expect(updates).toHaveLength(0);
  });

  it("clears stored headers on null and on empty object", async () => {
    const updated = { id: "f1", sourceType: "rss", httpHeaders: null };
    const { db, updates } = fakeDb([{ id: "f1", userId: "u1", sourceType: "rss" }], [updated]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const cleared = await action({
      request: putRequest({ httpHeaders: null }),
      params: { feedId: "f1" },
      context,
    });
    expect(cleared.status).toBe(200);
    expect(updates[0].httpHeaders).toBeNull();

    const emptied = await action({
      request: putRequest({ httpHeaders: {} }),
      params: { feedId: "f1" },
      context,
    });
    expect(emptied.status).toBe(200);
    expect(updates[1].httpHeaders).toBeNull();
  });

  it("rejects oversized header values with 400", async () => {
    const { db, updates } = fakeDb([{ id: "f1", userId: "u1", sourceType: "rss" }], []);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: putRequest({ httpHeaders: { Cookie: "a".repeat(4097) } }),
      params: { feedId: "f1" },
      context,
    });

    expect(response.status).toBe(400);
    expect(updates).toHaveLength(0);
  });
});
