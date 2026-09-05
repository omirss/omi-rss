import { describe, it, expect, beforeEach, vi } from "vitest";
import {
  tokenStore,
  addFeedPrefs,
  ApiError,
  SESSION_EXPIRED_EVENT,
  authApi,
  articlesApi,
  toCount,
} from "./client.js";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

describe("tokenStore", () => {
  beforeEach(() => {
    tokenStore.clear();
  });

  it("round-trips tokens and user", () => {
    tokenStore.setTokens({ token: "access-1", refreshToken: "refresh-1" });
    tokenStore.setUser({
      id: "u1",
      email: "a@example.com",
      username: "a",
      firstName: null,
      lastName: null,
      avatarUrl: null,
      role: "user",
      emailVerified: false,
      settings: {},
    });

    expect(tokenStore.getTokens()).toEqual({ token: "access-1", refreshToken: "refresh-1" });
    expect(tokenStore.getUser()?.username).toBe("a");
  });

  it("returns null user for corrupt JSON", () => {
    tokenStore.setUser({ id: "u1", email: "a@example.com", username: "a", firstName: null, lastName: null, avatarUrl: null, role: "user", emailVerified: false, settings: {} });
    expect(tokenStore.getUser()).not.toBeNull();
    expect(tokenStore.getTokens()).toBeNull();
  });

  it("clear removes everything", () => {
    tokenStore.setTokens({ token: "t", refreshToken: "r" });
    tokenStore.clear();
    expect(tokenStore.getTokens()).toBeNull();
    expect(tokenStore.getUser()).toBeNull();
  });
});

describe("request refresh rotation", () => {
  beforeEach(() => {
    tokenStore.clear();
    vi.unstubAllGlobals();
  });

  it("refreshes on 401, rotates tokens, and retries the original request", async () => {
    const calls: Array<{ path: string; auth?: string }> = [];
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input);
      calls.push({ path, auth: (init?.headers as Record<string, string>)?.Authorization });
      if (path === "/api/articles") {
        if (calls.filter((c) => c.path === "/api/articles").length === 1) {
          return jsonResponse({ error: "Token expired" }, 401);
        }
        return jsonResponse({ articles: [], pagination: { page: 1, limit: 20, total: 0, totalPages: 0 } });
      }
      if (path === "/api/auth/refresh") {
        return jsonResponse({ token: "access-2", refreshToken: "refresh-2" });
      }
      throw new Error(`unexpected fetch ${path}`);
    });
    vi.stubGlobal("fetch", fetchMock);

    tokenStore.setTokens({ token: "access-1", refreshToken: "refresh-1" });
    const result = await articlesApi.list();

    expect(result.articles).toEqual([]);
    expect(tokenStore.getTokens()).toEqual({ token: "access-2", refreshToken: "refresh-2" });
    expect(calls[0].auth).toBe("Bearer access-1");
    expect(calls[2].auth).toBe("Bearer access-2");
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it("clears the session and notifies when refresh fails", async () => {
    const dispatched: string[] = [];
    class FakeCustomEvent {
      type: string;
      constructor(type: string) {
        this.type = type;
      }
    }
    vi.stubGlobal("CustomEvent", FakeCustomEvent);
    vi.stubGlobal("dispatchEvent", (event: FakeCustomEvent) => {
      dispatched.push(event.type);
      return true;
    });

    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      if (path === "/api/articles") return jsonResponse({ error: "Token expired" }, 401);
      if (path === "/api/auth/refresh") return jsonResponse({ error: "Invalid refresh token" }, 401);
      throw new Error(`unexpected fetch ${path}`);
    });
    vi.stubGlobal("fetch", fetchMock);

    tokenStore.setTokens({ token: "access-1", refreshToken: "refresh-1" });
    await expect(articlesApi.list()).rejects.toThrow(ApiError);

    expect(tokenStore.getTokens()).toBeNull();
    expect(dispatched).toEqual([SESSION_EXPIRED_EVENT]);
  });

  it("does not attempt refresh for auth endpoints", async () => {
    const fetchMock = vi.fn(async () => jsonResponse({ error: "Invalid credentials" }, 401));
    vi.stubGlobal("fetch", fetchMock);

    tokenStore.setTokens({ token: "access-1", refreshToken: "refresh-1" });
    await expect(authApi.login({ emailOrUsername: "a", password: "b" })).rejects.toThrow("Invalid credentials");

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(tokenStore.getTokens()).toEqual({ token: "access-1", refreshToken: "refresh-1" });
  });
});

describe("toCount", () => {
  it("coerces numeric strings from postgres aggregates", () => {
    expect(toCount("42")).toBe(42);
    expect(toCount(7)).toBe(7);
    expect(toCount("not-a-number")).toBe(0);
  });
});

describe("addFeedPrefs", () => {
  beforeEach(() => {
    tokenStore.clear();
    addFeedPrefs.setFullTextDefault(true);
  });

  it("defaults full text on when nothing is stored", () => {
    expect(addFeedPrefs.getFullTextDefault()).toBe(true);
  });

  it("persists an opt-out and reads it back", () => {
    addFeedPrefs.setFullTextDefault(false);
    expect(addFeedPrefs.getFullTextDefault()).toBe(false);
    addFeedPrefs.setFullTextDefault(true);
    expect(addFeedPrefs.getFullTextDefault()).toBe(true);
  });
});

describe("feedsApi", () => {
  beforeEach(() => {
    tokenStore.clear();
    vi.unstubAllGlobals();
  });

  it("sends fullTextEnabled when subscribing", async () => {
    const bodies: unknown[] = [];
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      bodies.push(init?.body ? JSON.parse(String(init.body)) : null);
      return jsonResponse({ feed: { id: "f1", fullTextEnabled: true } });
    });
    vi.stubGlobal("fetch", fetchMock);
    tokenStore.setTokens({ token: "t", refreshToken: "r" });

    const { feedsApi } = await import("./client.js");
    await feedsApi.create({ url: "https://example.com/feed.xml", fullTextEnabled: true });

    expect(bodies[0]).toEqual({ url: "https://example.com/feed.xml", fullTextEnabled: true });
  });

  it("returns extractionStats from feed detail when present", async () => {
    const extractionStats = { scanned: 5, extracted: 3, failed: 1, pending: 1, windowLimit: 200 };
    const fetchMock = vi.fn(async () => jsonResponse({ feed: { id: "f1" }, stats: { totalArticles: 5, unreadArticles: 2 }, extractionStats }));
    vi.stubGlobal("fetch", fetchMock);
    tokenStore.setTokens({ token: "t", refreshToken: "r" });

    const { feedsApi } = await import("./client.js");
    const detail = await feedsApi.get("f1");

    expect(detail.extractionStats).toEqual(extractionStats);
    expect(detail.stats.unreadArticles).toBe(2);
  });
});
