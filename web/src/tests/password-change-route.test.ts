import { describe, it, expect, vi, beforeEach, afterAll } from "vitest";
import bcrypt from "bcrypt";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));

import { action } from "../routes/api/users/me/password.js";
import { getDb } from "../lib/api/db.js";

// POST /api/users/me/password: a successful change must bump
// users.token_version (bumpTokenVersion) like logout and password reset,
// revoking every outstanding access AND refresh token.

const OLD_PASSWORD = "old-password-123";
const NEW_PASSWORD = "new-password-456";
const OLD_HASH = bcrypt.hashSync(OLD_PASSWORD, 4);

function putRequest(body: unknown): Request {
  return new Request("http://localhost/api/users/me/password", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

function fakeDb(users: unknown[]) {
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
    select: () => selectQuery(users),
    update: () => ({
      set: (patch: Record<string, unknown>) => ({
        where: async () => {
          updates.push(patch);
        },
      }),
    }),
  };
  return { db, updates };
}

const context = { user: { id: "u1" } };

beforeEach(() => {
  vi.mocked(getDb).mockReset();
  process.env.BCRYPT_ROUNDS = "4";
});

afterAll(() => {
  process.env.BCRYPT_ROUNDS = "10";
});

describe("POST /api/users/me/password", () => {
  it("updates the hash and bumps the token version (revoking outstanding tokens)", async () => {
    const { db, updates } = fakeDb([{ id: "u1", passwordHash: OLD_HASH }]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: putRequest({ currentPassword: OLD_PASSWORD, newPassword: NEW_PASSWORD }),
      context,
    });

    expect(response.status).toBe(200);
    expect(updates).toHaveLength(2);
    const passwordPatch = updates[0] as { passwordHash?: string; updatedAt?: Date };
    expect(typeof passwordPatch.passwordHash).toBe("string");
    expect(passwordPatch.passwordHash).not.toBe(OLD_HASH);
    expect(await bcrypt.compare(NEW_PASSWORD, passwordPatch.passwordHash!)).toBe(true);
    // Second update is bumpTokenVersion's token_version increment.
    expect("tokenVersion" in updates[1]).toBe(true);
  });

  it("does not bump the token version when the current password is wrong", async () => {
    const { db, updates } = fakeDb([{ id: "u1", passwordHash: OLD_HASH }]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: putRequest({ currentPassword: "wrong-password", newPassword: NEW_PASSWORD }),
      context,
    });

    expect(response.status).toBe(401);
    expect(updates).toHaveLength(0);
  });

  it("returns 404 for a missing user", async () => {
    const { db } = fakeDb([]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: putRequest({ currentPassword: OLD_PASSWORD, newPassword: NEW_PASSWORD }),
      context,
    });

    expect(response.status).toBe(404);
  });
});
