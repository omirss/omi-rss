import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));

import { action as folderItemAction } from "../routes/api/folders/[folderId].js";
import { action as folderCreateAction } from "../routes/api/folders/index.js";
import { checkIfDescendant } from "../routes/api/folders/[folderId].js";
import { getDb } from "../lib/api/db.js";

// Folder tenancy + cycle guards (audit F014/F042): a folderId/parentId
// reference must belong to the caller, moves into own descendants are
// rejected, the descendant walk terminates on pre-existing cycles, and the
// DELETE pre-checks run inside one advisory-locked transaction.

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

function selectSequenceDb(selectResults: unknown[][], extra: Record<string, unknown> = {}) {
  let call = 0;
  const updates: Array<Record<string, unknown>> = [];
  const deletes: unknown[] = [];
  return {
    updates,
    deletes,
    db: {
      select: () => {
        const rows = selectResults[Math.min(call, selectResults.length - 1)] ?? [];
        call++;
        return thenable(rows);
      },
      update: () => ({
        set: (patch: Record<string, unknown>) => ({
          where: () => ({
            returning: async () => {
              updates.push(patch);
              return [{ id: "f1" }];
            },
          }),
        }),
      }),
      delete: () => ({
        where: (condition: unknown) => {
          deletes.push(condition);
          return Promise.resolve();
        },
      }),
      ...extra,
    },
  };
}

const context = { user: { id: "u1" } };

beforeEach(() => {
  vi.mocked(getDb).mockReset();
});

describe("folder tenancy", () => {
  it("POST /api/folders rejects a parentId owned by another user with 404", async () => {
    const { db } = selectSequenceDb([[]]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await folderCreateAction({
      request: new Request("http://localhost/api/folders", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: "New", parentId: "00000000-0000-0000-0000-00000000000b" }),
      }),
      context,
    });

    expect(response.status).toBe(404);
  });

  it("PUT /api/folders/:id rejects a folderId move target owned by another user with 404", async () => {
    const folder = { id: "folder-1", userId: "u1", name: "A", parentId: null };
    const { db, updates } = selectSequenceDb([[folder], []]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await folderItemAction({
      request: new Request("http://localhost/api/folders/folder-1", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ parentId: "00000000-0000-0000-0000-00000000000b" }),
      }),
      params: { folderId: "folder-1" },
      context,
    });

    expect(response.status).toBe(404);
    expect(updates).toHaveLength(0);
  });
});

describe("folder cycles", () => {
  it("rejects moving a folder under its own descendant with 400", async () => {
    const folderA = { id: "a", userId: "u1", name: "A", parentId: null };
    const folderB = { id: "b", userId: "u1", name: "B", parentId: "a" };
    // selects: existing folder, ownership check, descendant walk
    const { db, updates } = selectSequenceDb([[folderA], [{ id: "b" }], [folderA, folderB]]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await folderItemAction({
      request: new Request("http://localhost/api/folders/a", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ parentId: "b" }),
      }),
      params: { folderId: "a" },
      context,
    });

    expect(response.status).toBe(400);
    expect(updates).toHaveLength(0);
  });

  it("checkIfDescendant terminates on a pre-existing cycle instead of recursing forever", async () => {
    const cyclic = [
      { id: "a", parentId: "b" },
      { id: "b", parentId: "a" },
    ];
    const { db } = selectSequenceDb([cyclic]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    await expect(checkIfDescendant(db as never, "a", "zzz", "u1")).resolves.toBe(false);
  });
});

describe("folder delete transaction", () => {
  it("refuses to delete a folder that still has feeds (checks inside the tx)", async () => {
    const folder = { id: "folder-1", userId: "u1", name: "A", parentId: null };
    const txCalls: string[] = [];
    const tx = {
      execute: async () => {
        txCalls.push("advisory-lock");
      },
      select: () => thenable([{ count: 2 }]),
      delete: () => ({ where: () => Promise.resolve() }),
    };
    const { db, deletes } = selectSequenceDb([[folder]], { transaction: async (fn: (t: unknown) => Promise<void>) => fn(tx) });
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await folderItemAction({
      request: new Request("http://localhost/api/folders/folder-1", { method: "DELETE" }),
      params: { folderId: "folder-1" },
      context,
    });

    expect(response.status).toBe(400);
    expect(txCalls).toEqual(["advisory-lock"]);
    expect(deletes).toHaveLength(0);
  });
});
