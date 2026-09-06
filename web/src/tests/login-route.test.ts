import { describe, it, expect, vi, beforeEach, afterAll } from "vitest";
import bcrypt from "bcrypt";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));
vi.mock("../lib/api/rate-limit.js", () => ({
  authRateLimitKey: vi.fn(() => null),
  consumeAuthRateLimit: vi.fn(),
  consumeAnonAuthRateLimit: vi.fn(),
}));

import { action } from "../routes/api/auth/login.js";
import { getDb } from "../lib/api/db.js";
import { verifyAccessTokenClaims } from "../lib/api/tokens.js";

// POST /api/auth/login accepts emailOrUsername: a bare username must log in
// username-only accounts (registered without an email).

const PASSWORD = "a-long-password";
const PASSWORD_HASH = bcrypt.hashSync(PASSWORD, 4);

function loginRequest(emailOrUsername: string): Request {
  return new Request("http://localhost/api/auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ emailOrUsername, password: PASSWORD }),
  });
}

function fakeDb(user: unknown) {
  const updates: Record<string, unknown>[] = [];
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
    select: () => selectQuery(user ? [user] : []),
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

const NO_EMAIL_USER = {
  id: "u1",
  email: null,
  username: "alice",
  passwordHash: PASSWORD_HASH,
  isActive: true,
  role: "user",
  tokenVersion: 0,
};

beforeEach(() => {
  vi.mocked(getDb).mockReset();
  process.env.JWT_SECRET = "test-secret";
});

afterAll(() => {
  delete process.env.JWT_SECRET;
});

describe("POST /api/auth/login with a username", () => {
  it("logs in a username-only account and mints a token carrying the username", async () => {
    const { db, updates } = fakeDb(NO_EMAIL_USER);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({ request: loginRequest("alice") });

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      token: string;
      refreshToken: string;
      user: { username: string; email: string | null };
    };
    expect(body.user.username).toBe("alice");
    expect(body.user.email).toBeNull();
    const claims = verifyAccessTokenClaims(
      (await import("jsonwebtoken")).default.decode(body.token),
    );
    expect(claims?.username).toBe("alice");
    expect(updates[0]).toHaveProperty("lastLoginAt");
  });

  it("rejects a wrong password with 401", async () => {
    const { db } = fakeDb(NO_EMAIL_USER);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: new Request("http://localhost/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ emailOrUsername: "alice", password: "wrong-password" }),
      }),
    });

    expect(response.status).toBe(401);
  });
});
