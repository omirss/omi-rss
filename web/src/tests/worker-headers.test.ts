import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));

// The first test pays the dynamic import of worker.js (bullmq, rss-parser,
// neutron-data) which can exceed the 5s default under full-suite load.
vi.setConfig({ testTimeout: 20_000 });

// fetchDocument is mocked so the tests assert the WORKER wiring: the
// extract job must pass the feed's stored httpHeaders (loaded via the
// articles→feeds join) through to the document fetch — but only when the
// article URL is on the feed's own site (sameSiteHost).
vi.mock("../services/extraction.js", () => ({
  fetchDocument: vi.fn(async () => ({
    status: 200,
    body: new TextEncoder().encode("<html><head><title>t</title></head><body><p>enough text to pass readability thresholds and more words here to be safe about it</p></body></html>"),
    contentType: "text/html; charset=utf-8",
    etag: null,
    lastModified: null,
    finalUrl: "http://8.8.8.8/article",
  })),
  decodeBody: vi.fn((bytes: Uint8Array) => new TextDecoder().decode(bytes)),
  extractArticle: vi.fn(() => ({
    title: "t",
    contentHtml: "<p>extracted</p>",
    method: "readability" as const,
  })),
}));

import { getDb } from "../lib/api/db.js";
import { fetchDocument } from "../services/extraction.js";
import { sameSiteHost } from "../services/site-host.js";

function fakeDb(article: Record<string, unknown> | []) {
  const updates: Array<Record<string, unknown>> = [];
  return {
    updates,
    db: {
      select: () => ({
        from: () => ({
          innerJoin: () => ({
            where: () => ({
              limit: async () => (Array.isArray(article) ? [] : [article]),
            }),
          }),
        }),
      }),
      update: () => ({
        set: (patch: Record<string, unknown>) => ({
          where: async () => {
            updates.push(patch);
          },
        }),
      }),
    },
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(getDb).mockReset();
});

describe("processExtractArticle header wiring", () => {
  it("passes the feed's stored httpHeaders to fetchDocument for a same-host article", async () => {
    const { processExtractArticle } = await import("../worker.js");
    const { db, updates } = fakeDb({
      id: "a1",
      url: "http://8.8.8.8/article",
      feedUrl: "http://8.8.8.8/feed.xml",
      contentExtracted: null,
      httpHeaders: { cookie: "subscriber=token123", "x-key": "v" },
    });
    vi.mocked(getDb).mockResolvedValue(db as never);

    const result = await processExtractArticle("a1");

    expect(result.status).toBe("ok-readability");
    expect(vi.mocked(fetchDocument)).toHaveBeenCalledWith("http://8.8.8.8/article", undefined, {
      cookie: "subscriber=token123",
      "x-key": "v",
    });
    expect(updates).toHaveLength(1);
    expect(updates[0].contentExtracted).toBe("<p>extracted</p>");
  });

  it("passes undefined when the feed has no headers", async () => {
    const { processExtractArticle } = await import("../worker.js");
    const { db } = fakeDb({
      id: "a2",
      url: "http://8.8.8.8/other-article",
      feedUrl: "http://8.8.8.8/feed.xml",
      contentExtracted: null,
      httpHeaders: null,
    });
    vi.mocked(getDb).mockResolvedValue(db as never);

    await processExtractArticle("a2");

    expect(vi.mocked(fetchDocument)).toHaveBeenCalledWith("http://8.8.8.8/other-article", undefined, undefined);
  });

  it("drops the feed's httpHeaders when the article URL is a different host", async () => {
    const { processExtractArticle } = await import("../worker.js");
    const { db } = fakeDb({
      id: "a3",
      url: "http://9.9.9.9/article",
      feedUrl: "http://8.8.8.8/feed.xml",
      contentExtracted: null,
      httpHeaders: { cookie: "subscriber=token123" },
    });
    vi.mocked(getDb).mockResolvedValue(db as never);

    await processExtractArticle("a3");

    expect(vi.mocked(fetchDocument)).toHaveBeenCalledWith("http://9.9.9.9/article", undefined, undefined);
  });

  it("keeps the feed's httpHeaders when the article URL is on the feed's registrable domain", async () => {
    // ALLOW_PRIVATE_FEED_URLS skips the SSRF pre-check's DNS resolution so
    // the example.com hostnames stay offline-deterministic.
    process.env.ALLOW_PRIVATE_FEED_URLS = "true";
    try {
      const { processExtractArticle } = await import("../worker.js");
      const { db } = fakeDb({
        id: "a4",
        url: "https://www.example.com/article",
        feedUrl: "https://feeds.example.com/feed.xml",
        contentExtracted: null,
        httpHeaders: { cookie: "subscriber=token123" },
      });
      vi.mocked(getDb).mockResolvedValue(db as never);

      await processExtractArticle("a4");

      expect(vi.mocked(fetchDocument)).toHaveBeenCalledWith("https://www.example.com/article", undefined, {
        cookie: "subscriber=token123",
      });
    } finally {
      delete process.env.ALLOW_PRIVATE_FEED_URLS;
    }
  });
});

describe("sameSiteHost", () => {
  it("matches identical hosts and ignores ports", () => {
    expect(sameSiteHost("http://example.com/feed", "https://example.com:8443/article")).toBe(true);
    expect(sameSiteHost("http://8.8.8.8/f", "http://8.8.8.8:9999/a")).toBe(true);
  });

  it("matches subdomains of the same registrable domain (last two labels)", () => {
    expect(sameSiteHost("https://feeds.example.com/feed.xml", "https://www.example.com/article")).toBe(true);
    expect(sameSiteHost("https://example.com/feed.xml", "https://example.com/article")).toBe(true);
  });

  it("rejects different registrable domains", () => {
    expect(sameSiteHost("https://good.com/feed.xml", "https://evil.com/article")).toBe(false);
    expect(sameSiteHost("https://good.example.com/feed.xml", "https://evil.other.com/article")).toBe(false);
  });

  it("treats IP literals as exact-match only", () => {
    expect(sameSiteHost("http://127.0.0.1:3000/feed", "http://127.0.0.1:9999/item")).toBe(true);
    expect(sameSiteHost("http://127.0.0.1/feed", "http://127.0.0.2/item")).toBe(false);
    expect(sameSiteHost("http://127.0.0.1/feed", "http://localhost/item")).toBe(false);
    expect(sameSiteHost("http://[::1]/feed", "http://[::1]/item")).toBe(true);
    expect(sameSiteHost("http://[::1]/feed", "http://[::2]/item")).toBe(false);
  });

  it("treats single-label hosts as exact-match only", () => {
    expect(sameSiteHost("http://localhost/feed", "http://localhost/item")).toBe(true);
    expect(sameSiteHost("http://localhost/feed", "http://localhost.example.com/item")).toBe(false);
  });

  it("documents the naive multi-label public-suffix edge (co.uk)", () => {
    expect(sameSiteHost("https://a.example.co.uk/feed", "https://b.example.co.uk/article")).toBe(true);
  });

  it("returns false for unparseable URLs", () => {
    expect(sameSiteHost("not-a-url", "https://example.com/a")).toBe(false);
    expect(sameSiteHost("https://example.com/a", "")).toBe(false);
  });
});
