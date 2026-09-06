import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));
vi.mock("../data/runtime.js", () => ({ getDataRuntime: vi.fn() }));
vi.mock("./feed-fetch.js", () => ({
  fetchFeedXml: vi.fn(),
  assertSafeFeedUrl: vi.fn(async () => {}),
}));

import { getDb } from "../lib/api/db.js";
import { getDataRuntime } from "../data/runtime.js";
import { fetchFeedXml } from "./feed-fetch.js";

// R7 perf contract: the discover/search endpoints enrich from cache only
// and never block on live fetches; live metadata lands via the background
// warm (worker boot/cron or the first cold request).

// selectResults are returned per db.select() call in call order:
// [read-article join rows, readingStats rows, subscribed feed rows].
function makeDb(selectResults: unknown[][]) {
  let selectIndex = 0;
  const build = (rows: unknown[]) => {
    const q: Record<string, unknown> = {
      then: (onFulfilled: (value: unknown) => unknown, onRejected: (reason: unknown) => unknown) =>
        Promise.resolve(rows).then(onFulfilled, onRejected),
    };
    for (const method of ["from", "where", "innerJoin", "orderBy", "limit"]) {
      q[method] = () => q;
    }
    return q as never;
  };
  return {
    select: () => {
      const rows = selectResults[Math.min(selectIndex, selectResults.length - 1)] ?? [];
      selectIndex++;
      return build(rows);
    },
  } as never;
}

function makeCache(entries: Record<string, string>) {
  const sets: Array<{ key: string; value: string; ttl?: number }> = [];
  const cache = {
    get: vi.fn(async (key: string) => (key in entries ? entries[key] : null)),
    set: vi.fn(async (key: string, value: string, ttl?: number) => {
      sets.push({ key, value, ttl });
    }),
  };
  return { cache, sets };
}

// The single-flight warm is module state — each test needs a fresh module.
async function freshDiscovery() {
  vi.resetModules();
  return await import("./discovery.js");
}

const RSS_XML = (title: string) =>
  `<?xml version="1.0"?><rss version="2.0"><channel><title>${title}</title></channel></rss>`;

beforeEach(() => {
  vi.resetAllMocks();
});

describe("discoverFeeds cache-only enrichment", () => {
  it("serves curated suggestions on a cold cache without waiting for live metadata", async () => {
    const { feedDiscoveryService } = await freshDiscovery();
    vi.mocked(getDb).mockResolvedValue(makeDb([[], [], []]));
    const { cache } = makeCache({});
    vi.mocked(getDataRuntime).mockResolvedValue({ cache } as never);
    // Live fetches hang forever: if discoverFeeds awaited one, this test
    // would time out instead of resolving with the curated catalog.
    vi.mocked(fetchFeedXml).mockImplementation(() => new Promise<string>(() => {}));

    const suggestions = await feedDiscoveryService.discoverFeeds("u1");

    expect(suggestions.length).toBeGreaterThan(0);
    expect(suggestions.some((s) => s.title === "TechCrunch" && s.url === "https://techcrunch.com/feed/")).toBe(true);
  });

  it("enriches from warm metadata without triggering any live fetches", async () => {
    const { feedDiscoveryService, curatedFeedUrls } = await freshDiscovery();
    const entries: Record<string, string> = {};
    for (const url of curatedFeedUrls()) {
      entries[`feed:metadata:${url}`] = JSON.stringify({ title: `Live ${url}` });
    }
    vi.mocked(getDb).mockResolvedValue(makeDb([[], [], []]));
    const { cache } = makeCache(entries);
    vi.mocked(getDataRuntime).mockResolvedValue({ cache } as never);

    const suggestions = await feedDiscoveryService.discoverFeeds("u1");

    expect(fetchFeedXml).not.toHaveBeenCalled();
    expect(suggestions.some((s) => s.title === "Live https://techcrunch.com/feed/")).toBe(true);
  });

  it("does not re-trigger a warm pass on every request while feeds fail", async () => {
    const { feedDiscoveryService } = await freshDiscovery();
    vi.mocked(getDb).mockResolvedValue(makeDb([[], [], []]));
    const { cache } = makeCache({});
    vi.mocked(getDataRuntime).mockResolvedValue({ cache } as never);
    vi.mocked(fetchFeedXml).mockRejectedValue(new Error("feed down"));

    await feedDiscoveryService.discoverFeeds("u1");
    await new Promise((resolve) => setTimeout(resolve, 10));
    const afterFirst = vi.mocked(fetchFeedXml).mock.calls.length;
    expect(afterFirst).toBeGreaterThan(0);

    await feedDiscoveryService.discoverFeeds("u1");
    await new Promise((resolve) => setTimeout(resolve, 10));

    expect(vi.mocked(fetchFeedXml).mock.calls.length).toBe(afterFirst);
  });
});

describe("warmDiscoveryCatalog", () => {
  it("populates metadata cache entries for the whole curated catalog", async () => {
    const { warmDiscoveryCatalog, curatedFeedUrls } = await freshDiscovery();
    const { cache, sets } = makeCache({});
    vi.mocked(getDataRuntime).mockResolvedValue({ cache } as never);
    vi.mocked(fetchFeedXml).mockImplementation(async (url: string) => RSS_XML(`Live ${url}`));

    await warmDiscoveryCatalog();

    const setKeys = sets.map((s) => s.key);
    for (const url of curatedFeedUrls()) {
      expect(setKeys).toContain(`feed:metadata:${url}`);
    }
  });

  it("collapses concurrent calls into a single fetch pass", async () => {
    const { warmDiscoveryCatalog, curatedFeedUrls } = await freshDiscovery();
    const { cache, sets } = makeCache({});
    vi.mocked(getDataRuntime).mockResolvedValue({ cache } as never);
    let release: (() => void) | undefined;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    vi.mocked(fetchFeedXml).mockImplementation(async (url: string) => {
      await gate;
      return RSS_XML(`Live ${url}`);
    });

    const first = warmDiscoveryCatalog();
    const second = warmDiscoveryCatalog();

    expect(second).toBe(first);

    release!();
    await first;

    expect(fetchFeedXml).toHaveBeenCalledTimes(curatedFeedUrls().length);
    expect(sets.length).toBe(curatedFeedUrls().length);
  });
});
