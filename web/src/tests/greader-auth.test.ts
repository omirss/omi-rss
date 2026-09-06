import { describe, it, expect, beforeAll, vi } from "vitest";
import jwt from "jsonwebtoken";
import { AppError } from "../lib/api/errors.js";
import {
  signAccessToken,
  signGreaderAuthToken,
  signGreaderPostToken,
  verifyAccessTokenClaims,
  verifyGreaderToken,
} from "../lib/api/tokens.js";
import { parseGoogleLoginAuth, requireGreaderAuth, verifyGreaderPostToken } from "../lib/greader/auth.js";
import { readGreaderParams } from "../lib/greader/http.js";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));
vi.mock("../lib/greader/limit.js", () => ({ consumeGreaderRateLimit: vi.fn() }));

import { getDb } from "../lib/api/db.js";
import { consumeGreaderRateLimit } from "../lib/greader/limit.js";

beforeAll(() => {
  process.env.JWT_SECRET = "test-secret";
});

function greaderRequest(path: string, token?: string, method = "GET"): Request {
  return new Request(`http://localhost${path}`, {
    method,
    headers: token ? { Authorization: `GoogleLogin auth=${token}` } : {},
  });
}

const USER_ROW = {
  id: "u1",
  email: "a@example.com",
  username: "alice",
  role: "user",
  isActive: true,
  tokenVersion: 0,
  createdAt: new Date("2026-01-01T00:00:00Z"),
};

function fakeDb(userRows: unknown[]) {
  const q = {
    then: (res: (v: unknown) => unknown, rej: (r: unknown) => unknown) =>
      Promise.resolve(userRows).then(res, rej),
  };
  for (const m of ["from", "where", "limit"]) {
    (q as Record<string, unknown>)[m] = () => q;
  }
  return { select: () => q };
}

const next = () => vi.fn(async () => new Response("ok"));

describe("greader token issuance", () => {
  it("round-trips a greader-auth token", () => {
    const token = signGreaderAuthToken("u1", "a@example.com", "alice", "user", 3);
    const claims = verifyGreaderToken(token, "greader-auth");
    expect(claims).toEqual({ userId: "u1", tokenVersion: 3 });
  });

  it("greader-auth tokens expire in 7 days", () => {
    const payload = jwt.decode(signGreaderAuthToken("u1", "a", "b", "user")) as jwt.JwtPayload;
    expect((payload.exp! - payload.iat!) / 86400).toBe(7);
  });

  it("post tokens expire in 30 minutes", () => {
    const payload = jwt.decode(signGreaderPostToken("u1")) as jwt.JwtPayload;
    expect((payload.exp! - payload.iat!) / 60).toBe(30);
  });

  it("greader tokens cannot be replayed against the web API", () => {
    const token = signGreaderAuthToken("u1", "a@example.com", "alice", "user");
    expect(verifyAccessTokenClaims(jwt.decode(token))).toBeNull();
  });

  it("web access tokens and refresh tokens cannot hit the greader API", () => {
    const webToken = signAccessToken("u1", "a@example.com", "alice", "user");
    expect(verifyGreaderToken(webToken, "greader-auth")).toBeNull();
    expect(verifyGreaderToken(webToken, "greader-post")).toBeNull();
  });

  it("rejects wrong-type, expired and garbage tokens", () => {
    expect(verifyGreaderToken(signGreaderPostToken("u1"), "greader-auth")).toBeNull();
    expect(verifyGreaderToken("garbage", "greader-auth")).toBeNull();
    const expired = jwt.sign({ userId: "u1", type: "greader-auth" }, "test-secret", { expiresIn: -10 });
    expect(verifyGreaderToken(expired, "greader-auth")).toBeNull();
    const wrongSecret = jwt.sign({ userId: "u1", type: "greader-auth" }, "other-secret");
    expect(verifyGreaderToken(wrongSecret, "greader-auth")).toBeNull();
  });
});

describe("Authorization header parsing", () => {
  it("takes everything after GoogleLogin auth= verbatim", () => {
    expect(parseGoogleLoginAuth("GoogleLogin auth=abc/def+ghi=jkl")).toBe("abc/def+ghi=jkl");
    expect(parseGoogleLoginAuth("GoogleLogin auth=t")).toBe("t");
  });

  it("rejects other schemes and empty tokens", () => {
    expect(parseGoogleLoginAuth(null)).toBeNull();
    expect(parseGoogleLoginAuth("Bearer abc")).toBeNull();
    expect(parseGoogleLoginAuth("GoogleLogin auth=")).toBeNull();
  });
});

describe("requireGreaderAuth middleware", () => {
  it("short-circuits OPTIONS with 204 + CORS", async () => {
    const n = next();
    const result = await requireGreaderAuth(
      greaderRequest("/api/greader/reader/api/0/token", "x", "OPTIONS"),
      {},
      n
    );
    expect(result!.status).toBe(204);
    expect(result!.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(n).not.toHaveBeenCalled();
  });

  it("skips auth for ClientLogin", async () => {
    const n = next();
    const result = await requireGreaderAuth(
      greaderRequest("/api/greader/accounts/ClientLogin"),
      {},
      n
    );
    expect(await result!.text()).toBe("ok");
    expect(n).toHaveBeenCalled();
  });

  it("401s without a header", async () => {
    const n = next();
    const result = await requireGreaderAuth(
      greaderRequest("/api/greader/reader/api/0/user-info"),
      {},
      n
    );
    expect(result!.status).toBe(401);
    expect(n).not.toHaveBeenCalled();
  });

  it("401s a Bearer (web) token", async () => {
    const n = next();
    const webToken = signAccessToken("u1", "a@example.com", "alice", "user");
    const result = await requireGreaderAuth(
      greaderRequest("/api/greader/reader/api/0/user-info", webToken),
      {},
      n
    );
    expect(result!.status).toBe(401);
  });

  it("authenticates a valid greader token and sets context.user", async () => {
    vi.mocked(getDb).mockResolvedValue(fakeDb([USER_ROW]) as never);
    vi.mocked(consumeGreaderRateLimit).mockResolvedValue(undefined);
    const n = next();
    const token = signGreaderAuthToken("u1", "a@example.com", "alice", "user", 0);
    const context: Record<string, unknown> = {};
    const result = await requireGreaderAuth(
      greaderRequest("/api/greader/reader/api/0/user-info", token),
      context,
      n
    );
    expect(await result!.text()).toBe("ok");
    expect(consumeGreaderRateLimit).toHaveBeenCalledWith("u1");
    expect(context.user).toMatchObject({ id: "u1", username: "alice", tokenVersion: 0 });
  });

  it("401s on unknown user, disabled user, or tokenVersion mismatch", async () => {
    const token = signGreaderAuthToken("u1", "a@example.com", "alice", "user", 0);
    for (const row of [
      [],
      [{ ...USER_ROW, isActive: false }],
      [{ ...USER_ROW, tokenVersion: 7 }],
    ]) {
      vi.mocked(getDb).mockResolvedValue(fakeDb(row) as never);
      const n = next();
      const result = await requireGreaderAuth(
        greaderRequest("/api/greader/reader/api/0/user-info", token),
        {},
        n
      );
      expect(result!.status).toBe(401);
      expect(n).not.toHaveBeenCalled();
    }
  });

  it("surfaces the 429 from the greader limiter as text", async () => {
    vi.mocked(getDb).mockResolvedValue(fakeDb([USER_ROW]) as never);
    vi.mocked(consumeGreaderRateLimit).mockRejectedValue(
      new AppError("Too many requests, please try again later", 429)
    );
    const n = next();
    const token = signGreaderAuthToken("u1", "a@example.com", "alice", "user", 0);
    const result = await requireGreaderAuth(
      greaderRequest("/api/greader/reader/api/0/user-info", token),
      {},
      n
    );
    expect(result!.status).toBe(429);
    expect(await result!.text()).toContain("Too many requests");
  });
});

describe("T (post) token policy", () => {
  const user = { id: "u1", email: "a@x", username: "alice", role: "user", tokenVersion: 0, createdAt: new Date() };

  async function paramsWith(body: string): Promise<ReturnType<typeof readGreaderParams>> {
    return readGreaderParams(
      new Request("http://localhost/x", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body,
      })
    );
  }

  it("tolerates absent and empty T (FeedMe)", async () => {
    expect(verifyGreaderPostToken(await paramsWith("i=1"), user)).toBeNull();
    expect(verifyGreaderPostToken(await paramsWith("T=&i=1"), user)).toBeNull();
  });

  it("401 + X-Reader-Google-Bad-Token on garbage T", async () => {
    const result = verifyGreaderPostToken(await paramsWith("T=garbage&i=1"), user);
    expect(result).toBeInstanceOf(Response);
    expect(result!.status).toBe(401);
    expect(result!.headers.get("X-Reader-Google-Bad-Token")).toBe("true");
  });

  it("401 on an auth-type token presented as T", async () => {
    const authToken = signGreaderAuthToken("u1", "a@x", "alice", "user", 0);
    expect(verifyGreaderPostToken(await paramsWith(`T=${encodeURIComponent(authToken)}&i=1`), user)).toBeInstanceOf(
      Response
    );
  });

  it("accepts a fresh post token for the same user", async () => {
    const postToken = signGreaderPostToken("u1", 0);
    expect(verifyGreaderPostToken(await paramsWith(`T=${encodeURIComponent(postToken)}&i=1`), user)).toBeNull();
  });

  it("401 on a post token of a different user or stale tokenVersion", async () => {
    const other = signGreaderPostToken("u2", 0);
    expect(verifyGreaderPostToken(await paramsWith(`T=${encodeURIComponent(other)}&i=1`), user)).toBeInstanceOf(
      Response
    );
    const stale = signGreaderPostToken("u1", 5);
    expect(verifyGreaderPostToken(await paramsWith(`T=${encodeURIComponent(stale)}&i=1`), user)).toBeInstanceOf(
      Response
    );
  });

  it("401 on an expired post token (models the client refetch loop)", async () => {
    const expired = jwt.sign({ userId: "u1", tokenVersion: 0, type: "greader-post" }, "test-secret", {
      expiresIn: -10,
    });
    expect(verifyGreaderPostToken(await paramsWith(`T=${encodeURIComponent(expired)}&i=1`), user)).toBeInstanceOf(
      Response
    );
  });
});
