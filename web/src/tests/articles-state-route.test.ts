import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));

import { action as stateAction } from "../routes/api/articles/[articleId]/state.js";
import { action as settingsAction } from "../routes/api/users/me/settings.js";
import { getDb } from "../lib/api/db.js";

// State/settings write semantics (audit F029/F030/F031): clearing a flag
// clears its timestamp, a repeated true keeps the original event time (the
// conflict SET references the current row), and settings merge in SQL
// against the locked row instead of a JS read-merge-write.

function thenable(rows: unknown[]) {
  const q: Record<string, unknown> = {
    then: (onFulfilled: (value: unknown) => unknown, onRejected: (reason: unknown) => unknown) =>
      Promise.resolve(rows).then(onFulfilled, onRejected),
  };
  for (const method of ["from", "innerJoin", "leftJoin", "where", "limit"]) {
    q[method] = () => q;
  }
  return q as never;
}

const context = { user: { id: "u1" } };

beforeEach(() => {
  vi.mocked(getDb).mockReset();
});

describe("PUT /api/articles/:id/state", () => {
  function captureDb() {
    const writes: Array<{ values?: Record<string, unknown>; set?: Record<string, unknown> }> = [];
    const db = {
      select: () => thenable([{ id: "a1" }]),
      insert: () => ({
        values: (values: Record<string, unknown>) => ({
          onConflictDoUpdate: (conflict: { set: Record<string, unknown> }) => {
            writes.push({ values, set: conflict.set });
            return Promise.resolve();
          },
        }),
      }),
    };
    return { db, writes };
  }

  function putRequest(body: unknown): Request {
    return new Request("http://localhost/api/articles/a1/state", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  }

  it("sets readAt on true and CLEARS it on false (insert values and conflict set agree)", async () => {
    const { db, writes } = captureDb();
    vi.mocked(getDb).mockResolvedValue(db as never);

    const on = await stateAction({ request: putRequest({ isRead: true }), params: { articleId: "a1" }, context });
    expect(on.status).toBe(200);
    expect(writes[0].values?.readAt).toBeInstanceOf(Date);
    expect(writes[0].set?.readAt).toBeTruthy();

    const off = await stateAction({ request: putRequest({ isRead: false }), params: { articleId: "a1" }, context });
    expect(off.status).toBe(200);
    expect(writes[1].values?.readAt).toBeNull();
    expect(writes[1].set?.readAt).toBeNull();
  });

  it("starred follows the same timestamp contract", async () => {
    const { db, writes } = captureDb();
    vi.mocked(getDb).mockResolvedValue(db as never);

    await stateAction({ request: putRequest({ isStarred: true }), params: { articleId: "a1" }, context });
    expect(writes[0].values?.starredAt).toBeInstanceOf(Date);

    await stateAction({ request: putRequest({ isStarred: false }), params: { articleId: "a1" }, context });
    expect(writes[1].values?.starredAt).toBeNull();
    expect(writes[1].set?.starredAt).toBeNull();
  });

  it("404s for articles the caller does not own", async () => {
    const db = {
      select: () => thenable([]),
      insert: () => {
        throw new Error("must not write");
      },
    };
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await stateAction({ request: putRequest({ isRead: true }), params: { articleId: "a1" }, context });
    expect(response.status).toBe(404);
  });
});

describe("PUT /api/users/me/settings", () => {
  it("merges settings in SQL without a pre-select (no read-merge-write window)", async () => {
    const selects: number[] = [];
    const sets: Array<Record<string, unknown>> = [];
    const db = {
      select: () => {
        selects.push(1);
        return thenable([]);
      },
      update: () => ({
        set: (patch: Record<string, unknown>) => ({
          where: () => ({
            returning: async () => {
              sets.push(patch);
              return [{ id: "u1", settings: { theme: "dark", dense: true } }];
            },
          }),
        }),
      }),
    };
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await settingsAction({
      request: new Request("http://localhost/api/users/me/settings", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ settings: { dense: true } }),
      }),
      context,
    });

    expect(response.status).toBe(200);
    expect(selects).toHaveLength(0);
    expect(sets).toHaveLength(1);
    expect("settings" in sets[0]).toBe(true);
    const body = (await response.json()) as { settings: Record<string, unknown> };
    expect(body.settings).toEqual({ theme: "dark", dense: true });
  });

  it("404s when the update matches no row", async () => {
    const db = {
      update: () => ({
        set: () => ({
          where: () => ({
            returning: async () => [],
          }),
        }),
      }),
    };
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await settingsAction({
      request: new Request("http://localhost/api/users/me/settings", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ settings: { a: 1 } }),
      }),
      context,
    });

    expect(response.status).toBe(404);
  });
});
