import { describe, it, expect, beforeAll, vi, beforeEach } from "vitest";
import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));
vi.mock("../lib/api/rate-limit.js", () => ({
  authRateLimitKey: vi.fn(() => null),
  consumeAuthRateLimit: vi.fn(),
  consumeAnonAuthRateLimit: vi.fn(),
}));

import { action, loader } from "../routes/api/greader/[...path].js";
import { getDb } from "../lib/api/db.js";
import { consumeAnonAuthRateLimit } from "../lib/api/rate-limit.js";

// ClientLogin contract: form fields Email/Passwd, text/plain SID/LSID/Auth
// lines on success, Error=BadAuthentication on failure, and the shared
// fail-closed auth limiter in front of the bcrypt compare.

beforeAll(() => {
  process.env.JWT_SECRET = "test-secret";
});

const PASSWORD = "pw-api";

function clientLoginRequest(body: string, method = "POST"): Request {
  return new Request("http://localhost/api/greader/accounts/ClientLogin", {
    method,
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
}

function fakeDb(userRows: unknown[]) {
  const updates: Array<Record<string, unknown>> = [];
  const selectQuery = {
    then: (res: (v: unknown) => unknown, rej: (r: unknown) => unknown) =>
      Promise.resolve(userRows).then(res, rej),
  };
  for (const m of ["from", "where", "limit"]) {
    (selectQuery as Record<string, unknown>)[m] = () => selectQuery;
  }
  const db = {
    select: () => selectQuery,
    update: () => ({
      set: (patch: Record<string, unknown>) => ({
        where: () => {
          updates.push(patch);
          return Promise.resolve();
        },
      }),
    }),
  };
  return { db, updates };
}


const USER = {
  id: "u1",
  email: "alice@example.com",
  username: "alice",
  role: "user",
  isActive: true,
  tokenVersion: 2,
  passwordHash: "",
};

beforeAll(async () => {
  USER.passwordHash = await bcrypt.hash(PASSWORD, 4);
});

beforeEach(() => {
  vi.mocked(getDb).mockReset();
  vi.mocked(consumeAnonAuthRateLimit).mockReset().mockResolvedValue(undefined);
});

describe("POST /api/greader/accounts/ClientLogin", () => {
  it("returns 400 Error=BadAuthentication when Email/Passwd are missing", async () => {
    const response = await action({
      request: clientLoginRequest("service=reader&client=x"),
      params: { path: "accounts/ClientLogin" },
      context: {},
    });
    expect(response.status).toBe(400);
    expect(await response.text()).toContain("Error=BadAuthentication");
  });

  it("returns 401 Error=BadAuthentication on unknown user", async () => {
    const { db } = fakeDb([]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    const response = await action({
      request: clientLoginRequest(`Email=alice&Passwd=${PASSWORD}`),
      params: { path: "accounts/ClientLogin" },
      context: {},
    });
    expect(response.status).toBe(401);
    expect(await response.text()).toContain("Error=BadAuthentication");
  });

  it("returns 401 on wrong password and on disabled accounts", async () => {
    const wrong = fakeDb([USER]);
    vi.mocked(getDb).mockResolvedValue(wrong.db as never);
    const bad = await action({
      request: clientLoginRequest("Email=alice&Passwd=wrong"),
      params: { path: "accounts/ClientLogin" },
      context: {},
    });
    expect(bad.status).toBe(401);

    const disabled = fakeDb([{ ...USER, isActive: false }]);
    vi.mocked(getDb).mockResolvedValue(disabled.db as never);
    const inactive = await action({
      request: clientLoginRequest(`Email=alice&Passwd=${PASSWORD}`),
      params: { path: "accounts/ClientLogin" },
      context: {},
    });
    expect(inactive.status).toBe(401);
  });

  it("returns SID/LSID/Auth lines with a 7d greader-auth JWT", async () => {
    const { db, updates } = fakeDb([USER]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: clientLoginRequest(`Email=alice&Passwd=${PASSWORD}`),
      params: { path: "accounts/ClientLogin" },
      context: {},
    });

    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toContain("text/plain");
    const body = await response.text();
    const lines = body.trim().split("\n");
    expect(lines).toHaveLength(3);
    expect(lines[0].startsWith("SID=")).toBe(true);
    expect(lines[1].startsWith("LSID=")).toBe(true);
    expect(lines[2].startsWith("Auth=")).toBe(true);
    const authToken = lines[2].slice("Auth=".length);
    const payload = jwt.decode(authToken) as jwt.JwtPayload;
    expect(payload.type).toBe("greader-auth");
    expect(payload.userId).toBe("u1");
    expect(payload.tokenVersion).toBe(2);
    expect((payload.exp! - payload.iat!) / 86400).toBe(7);
    // SID echoes the Auth value (FreshRSS parity)
    expect(lines[0].slice("SID=".length)).toBe(authToken);
    expect(updates[0]).toHaveProperty("lastLoginAt");
  });

  it("accepts the username in Email and credentials on GET too", async () => {
    const { db } = fakeDb([USER]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    let response = await action({
      request: clientLoginRequest(`Email=alice@example.com&Passwd=${PASSWORD}`),
      params: { path: "accounts/ClientLogin" },
      context: {},
    });
    expect(response.status).toBe(200);

    response = await loader({
      request: new Request(
        `http://localhost/api/greader/accounts/ClientLogin?Email=alice&Passwd=${encodeURIComponent(PASSWORD)}`
      ),
      params: { path: "accounts/ClientLogin" },
      context: {},
    }).catch((error: unknown) => error as Response);
    expect(response).toBeInstanceOf(Response);
    expect(response.status).toBe(200);
  });

  it("runs through the shared fail-closed auth limiter", async () => {
    const { db } = fakeDb([USER]);
    vi.mocked(getDb).mockResolvedValue(db as never);
    await action({
      request: clientLoginRequest(`Email=alice&Passwd=${PASSWORD}`),
      params: { path: "accounts/ClientLogin" },
      context: {},
    });
    expect(consumeAnonAuthRateLimit).toHaveBeenCalledWith("alice");
  });

  it("maps limiter rejections to text responses", async () => {
    vi.mocked(consumeAnonAuthRateLimit).mockRejectedValueOnce(new Error("redis down"));
    const response = await action({
      request: clientLoginRequest(`Email=alice&Passwd=${PASSWORD}`),
      params: { path: "accounts/ClientLogin" },
      context: {},
    });
    expect(response.status).toBe(500);

    const { AppError } = await import("../lib/api/errors.js");
    vi.mocked(consumeAnonAuthRateLimit).mockRejectedValueOnce(new AppError("Too many requests, please try again later", 429));
    const limited = await action({
      request: clientLoginRequest(`Email=alice&Passwd=${PASSWORD}`),
      params: { path: "accounts/ClientLogin" },
      context: {},
    });
    expect(limited.status).toBe(429);
    expect(await limited.text()).toContain("Too many requests");
  });
});
