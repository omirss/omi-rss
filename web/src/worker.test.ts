import { describe, it, expect, vi, beforeEach } from "vitest";
import { isFeedDue, extractionBudgetExceeded, articleExtractionOutcome } from "./worker.js";
import { getDb } from "./lib/api/db.js";

// DNS is mocked so transient-vs-terminal classification is deterministic:
// unknown hostnames fail resolution (transient); mapped ones resolve.
vi.mock("node:dns/promises", () => ({
  lookup: vi.fn(async (hostname: string) => {
    const records: Record<string, string> = {
      "blocked.example": "10.0.0.5",
      "ok.example": "93.184.216.34",
    };
    if (!(hostname in records)) {
      const error = new Error(`getaddrinfo ENOTFOUND ${hostname}`) as NodeJS.ErrnoException;
      error.code = "ENOTFOUND";
      throw error;
    }
    return { address: records[hostname], family: 4 };
  }),
}));

vi.mock("./lib/api/db.js", () => ({
  getDb: vi.fn(),
}));

// Unit tests for the update-all due-feed filter, extracted from the Express
// SQL: active AND (never fetched OR fetched strictly longer than
// updateInterval minutes ago). NULL interval arithmetic never becomes due
// on its own, matching the SQL comparison.

const NOW = new Date("2026-01-01T12:00:00.000Z");

function minutesAgo(minutes: number): Date {
  return new Date(NOW.getTime() - minutes * 60 * 1000);
}

describe("isFeedDue", () => {
  it("should be due when never fetched", () => {
    expect(isFeedDue({ isActive: true, lastFetchedAt: null, updateInterval: 30 }, NOW)).toBe(true);
  });

  it("should be due when fetched with a null interval but never fetched wins", () => {
    expect(isFeedDue({ isActive: true, lastFetchedAt: null, updateInterval: null }, NOW)).toBe(true);
  });

  it("should not be due before the interval elapses", () => {
    expect(isFeedDue({ isActive: true, lastFetchedAt: minutesAgo(10), updateInterval: 30 }, NOW)).toBe(false);
  });

  it("should not be due exactly at the interval boundary", () => {
    expect(isFeedDue({ isActive: true, lastFetchedAt: minutesAgo(30), updateInterval: 30 }, NOW)).toBe(false);
  });

  it("should be due after the interval elapses", () => {
    expect(isFeedDue({ isActive: true, lastFetchedAt: minutesAgo(31), updateInterval: 30 }, NOW)).toBe(true);
  });

  it("should honor per-feed update intervals", () => {
    const fetched = minutesAgo(10);
    expect(isFeedDue({ isActive: true, lastFetchedAt: fetched, updateInterval: 5 }, NOW)).toBe(true);
    expect(isFeedDue({ isActive: true, lastFetchedAt: fetched, updateInterval: 60 }, NOW)).toBe(false);
  });

  it("should never be due when inactive", () => {
    expect(isFeedDue({ isActive: false, lastFetchedAt: null, updateInterval: 30 }, NOW)).toBe(false);
    expect(isFeedDue({ isActive: false, lastFetchedAt: minutesAgo(120), updateInterval: 30 }, NOW)).toBe(false);
  });

  it("should not be due with a fetched feed and a null interval (SQL NULL comparison)", () => {
    expect(isFeedDue({ isActive: true, lastFetchedAt: minutesAgo(120), updateInterval: null }, NOW)).toBe(false);
  });
});

describe("extractionBudgetExceeded", () => {
  const startedAt = 1000000;

  it("allows extraction while under both the article count and time budget", () => {
    expect(extractionBudgetExceeded(startedAt, 0, startedAt + 1000)).toBe(false);
    expect(extractionBudgetExceeded(startedAt, 19, startedAt + 9999)).toBe(false);
  });

  it("stops after 20 articles", () => {
    expect(extractionBudgetExceeded(startedAt, 20, startedAt + 1000)).toBe(true);
    expect(extractionBudgetExceeded(startedAt, 25, startedAt + 1000)).toBe(true);
  });

  it("stops after 10 seconds even with articles remaining", () => {
    expect(extractionBudgetExceeded(startedAt, 3, startedAt + 10000)).toBe(true);
    expect(extractionBudgetExceeded(startedAt, 3, startedAt + 15000)).toBe(true);
  });
});

describe("articleExtractionOutcome", () => {
  it("skips safely on unsafe article URLs without fetching (SSRF)", async () => {
    expect(await articleExtractionOutcome({ url: "file:///etc/passwd" }, null)).toBe("skip-unsafe-url");
    expect(await articleExtractionOutcome({ url: "http://127.0.0.1:6380/x" }, null)).toBe("skip-unsafe-url");
    expect(await articleExtractionOutcome({ url: "https://192.168.1.10/internal" }, null)).toBe("skip-unsafe-url");
    expect(await articleExtractionOutcome({ url: "https://blocked.example/x" }, null)).toBe("skip-unsafe-url");
  });

  it("fetches safe literal-IP URLs without DNS lookups", async () => {
    expect(await articleExtractionOutcome({ url: "https://8.8.8.8/post" }, null)).toBe("fetch");
  });

  it("defers transient DNS failures instead of terminal-skipping them", async () => {
    expect(await articleExtractionOutcome({ url: "https://this-host-does-not-resolve.example/x" }, null)).toBe(
      "defer-transient",
    );
  });

  it("is terminal once an article has been extracted (fetch once, never re-fetch)", async () => {
    expect(await articleExtractionOutcome({ url: "https://8.8.8.8/post" }, "")).toBe("already-extracted");
    expect(await articleExtractionOutcome({ url: "https://8.8.8.8/post" }, "<p>done</p>")).toBe("already-extracted");
  });

  it("handles missing articles and empty URLs", async () => {
    expect(await articleExtractionOutcome(undefined, null)).toBe("missing");
    expect(await articleExtractionOutcome({ url: "" }, null)).toBe("skip-no-url");
  });
});

describe("DNS-transient vs terminal classification in processExtractArticle", () => {
  interface InsertCapture {
    values: unknown[];
    conflictTarget: unknown;
  }

  function fakeDb(article: { id: string; url: string; contentExtracted: string | null } | []) {
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
            where: () => ({
              limit: async () => (Array.isArray(article) ? [] : [article]),
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

  it("leaves contentExtracted NULL on transient DNS failures (backfill retries later)", async () => {
    const { db, updates } = fakeDb({ id: "a1", url: "https://no-such-host.example/post", contentExtracted: null });
    vi.mocked(getDb).mockResolvedValue(db as unknown as never);

    const { processExtractArticle } = await import("./worker.js");
    const result = await processExtractArticle("a1");

    expect(result.status).toBe("deferred-transient");
    expect(updates).toHaveLength(0);
  });

  it("stores '' (terminal) on validation failures like blocked ranges", async () => {
    const { db, updates } = fakeDb({ id: "a2", url: "http://127.0.0.1:6380/x", contentExtracted: null });
    vi.mocked(getDb).mockResolvedValue(db as unknown as never);

    const { processExtractArticle } = await import("./worker.js");
    const result = await processExtractArticle("a2");

    expect(result.status).toBe("skip-unsafe-url");
    expect(updates).toHaveLength(1);
    expect(updates[0].contentExtracted).toBe("");
  });
});

describe("resolveArticleUrl", () => {
  it("resolves relative item links against the feed site URL", async () => {
    const { resolveArticleUrl } = await import("./worker.js");
    expect(resolveArticleUrl("/posts/x", "https://example.com/feed.xml")).toBe("https://example.com/posts/x");
    expect(resolveArticleUrl("posts/x", "https://example.com/blog/")).toBe("https://example.com/blog/posts/x");
  });

  it("keeps absolute links unchanged", async () => {
    const { resolveArticleUrl } = await import("./worker.js");
    expect(resolveArticleUrl("https://other.example/a", "https://example.com/")).toBe("https://other.example/a");
  });

  it("returns '' for missing links and passes through unresolvable values", async () => {
    const { resolveArticleUrl } = await import("./worker.js");
    expect(resolveArticleUrl(undefined, "https://example.com/")).toBe("");
    expect(resolveArticleUrl("not a url \u0000", null)).toBe("not a url \u0000");
  });
});

describe("createPageFeedStore", () => {
  function sqlFragmentText(fragment: unknown): string {
    const chunks = (fragment as { queryChunks?: unknown[] }).queryChunks ?? [];
    return chunks
      .map((chunk) => {
        const value = (chunk as { value?: unknown }).value;
        if (Array.isArray(value)) return value.join("");
        if (typeof chunk === "string") return chunk;
        return "";
      })
      .join("");
  }

  function captureDb(returningRows: Array<{ id: string }> = [{ id: "n1" }]) {
    const inserts: Array<{ values: unknown; conflictTarget: unknown }> = [];
    const updates: Array<Record<string, unknown>> = [];
    const db = {
      insert: () => ({
        values: (values: unknown) => ({
          onConflictDoNothing: (conflict: { target: unknown }) => ({
            returning: async () => {
              inserts.push({ values, conflictTarget: conflict.target });
              return returningRows;
            },
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
    };
    return { db, inserts, updates };
  }

  it("inserts all page items in one multi-row INSERT with conflict tolerance", async () => {
    const { createPageFeedStore } = await import("./worker.js");
    const { db, inserts } = captureDb([{ id: "n1" }, { id: "n2" }]);

    const inserted = await createPageFeedStore(db as never).insertItems(
      "feed-1",
      [
        { guid: "g1", title: "One", link: "https://example.com/1", contentHtml: "<p>1</p>" },
        { guid: "g2", title: "Two", link: null, contentHtml: "<p>2</p>" },
      ],
      "https://example.com/page",
    );

    expect(inserted).toBe(2);
    expect(inserts).toHaveLength(1);
    expect(Array.isArray(inserts[0].values)).toBe(true);
    expect((inserts[0].values as unknown[]).length).toBe(2);
    expect(inserts[0].conflictTarget).toBeTruthy();
  });

  it("markSelectorMiss writes the structured pageStatus alongside the human message", async () => {
    const { createPageFeedStore } = await import("./worker.js");
    const { db, updates } = captureDb();

    await createPageFeedStore(db as never).markSelectorMiss("feed-1", "Selector matched 0 elements on https://x");

    expect(updates).toHaveLength(1);
    expect(updates[0].lastFetchError).toContain("matched 0 elements");
    expect(sqlFragmentText(updates[0].settings)).toContain('"pageStatus":"selector-miss"');
  });

  it("markSuccess merges the structured pageStatus patch into settings", async () => {
    const { createPageFeedStore } = await import("./worker.js");
    const { db, updates } = captureDb();

    await createPageFeedStore(db as never).markSuccess("feed-1", { pageStatus: "ok", pageEtag: '"v1"' });

    expect(updates).toHaveLength(1);
    expect(updates[0].lastFetchError).toBeNull();
    expect(sqlFragmentText(updates[0].settings)).toContain("pageStatus");
  });
});
