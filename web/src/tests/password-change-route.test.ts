import { describe, it, expect, vi, beforeEach, afterAll } from "vitest";
import bcrypt from "bcrypt";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));

import { action } from "../routes/api/users/me/password.js";
import { getDb } from "../lib/api/db.js";

// POST /api/users/me/password: a successful change bumps
// users.token_version atomically with the password write (revoking every
// outstanding access AND refresh token) and clears any pending reset token.

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
        where: () => ({
          returning: async () => {
            updates.push(patch);
            return [{ id: "u1" }];
          },
        }),
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
  it("updates the hash, clears pending reset tokens and bumps the token version in one statement", async () => {
    const { db, updates } = fakeDb([{ id: "u1", passwordHash: OLD_HASH }]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: putRequest({ currentPassword: OLD_PASSWORD, newPassword: NEW_PASSWORD }),
      context,
    });

    expect(response.status).toBe(200);
    expect(updates).toHaveLength(1);
    const patch = updates[0] as { passwordHash?: string; tokenVersion?: unknown; passwordResetToken?: null };
    expect(typeof patch.passwordHash).toBe("string");
    expect(patch.passwordHash).not.toBe(OLD_HASH);
    expect(await bcrypt.compare(NEW_PASSWORD, patch.passwordHash!)).toBe(true);
    expect("tokenVersion" in patch).toBe(true);
    expect(patch.passwordResetToken).toBeNull();
  });

  it("conflicts when the password was changed concurrently (precondition hash no longer matches)", async () => {
    const { db, updates } = fakeDb([{ id: "u1", passwordHash: OLD_HASH }]);
    vi.mocked(getDb).mockResolvedValue({
      ...db,
      update: () => ({
        set: (patch: Record<string, unknown>) => ({
          where: () => ({
            returning: async () => {
              updates.push(patch);
              return [];
            },
          }),
        }),
      }),
    } as never);

    const response = await action({
      request: putRequest({ currentPassword: OLD_PASSWORD, newPassword: NEW_PASSWORD }),
      context,
    });

    expect(response.status).toBe(409);
    expect(updates).toHaveLength(1);
  });

  it("does not write when the current password is wrong", async () => {
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
