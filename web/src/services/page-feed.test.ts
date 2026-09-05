import { describe, it, expect, vi } from "vitest";
import crypto from "node:crypto";
import {
  validatePageFeedInput,
  runPageFeedUpdate,
  pageFeedConditionalState,
  type PageFeedRecord,
  type PageFeedStore,
} from "./page-feed.js";
import { extractPageItems, normalizeItemIdentity, type FetchedDocument } from "./extraction.js";
import { AppError } from "../lib/api/errors.js";

// Page-feed resilience tests with a fake fetcher and store — no network,
// no database. Semantics: conditional GET, hash identity, keep-last-good
// on selector miss (RSSHub MIT patterns; see spike RESULTS.md Q5).

const PAGE_URL = "https://example.com/blog";
const SELECTOR = "article.post";
const PAGE_HTML = `
  <html><body><main>
    <article class="post"><h2><a href="/posts/one">First</a></h2><p>One</p></article>
    <article class="post"><h2><a href="/posts/two">Second</a></h2><p>Two</p></article>
  </main></body></html>`;
const MISS_HTML = `<html><body><div>redesigned, selector no longer matches</div></body></html>`;

function documentResponse(html: string, etag: string | null = '"v1"'): FetchedDocument {
  return {
    status: 200,
    body: new TextEncoder().encode(html),
    contentType: "text/html; charset=utf-8",
    etag,
    lastModified: "Wed, 01 Jan 2026 00:00:00 GMT",
    finalUrl: PAGE_URL,
  };
}

interface StoreCalls {
  inserted: { feedId: string; items: ReturnType<typeof extractPageItems> }[];
  successes: { feedId: string; settingsPatch: Record<string, unknown> }[];
  misses: { feedId: string; message: string }[];
  existingGuids: Set<string>;
}

function fakeStore(): { store: PageFeedStore; calls: StoreCalls } {
  const calls: StoreCalls = { inserted: [], successes: [], misses: [], existingGuids: new Set() };
  const store: PageFeedStore = {
    insertItems: async (feedId, items) => {
      calls.inserted.push({ feedId, items });
      let inserted = 0;
      for (const item of items) {
        if (!calls.existingGuids.has(item.guid)) {
          calls.existingGuids.add(item.guid);
          inserted++;
        }
      }
      return inserted;
    },
    markSuccess: async (feedId, settingsPatch) => {
      calls.successes.push({ feedId, settingsPatch });
    },
    markSelectorMiss: async (feedId, message) => {
      calls.misses.push({ feedId, message });
    },
  };
  return { store, calls };
}

function feedRecord(settings: Record<string, unknown> = {}): PageFeedRecord {
  return { id: "feed-1", pageUrl: PAGE_URL, pageSelector: SELECTOR, settings };
}

describe("runPageFeedUpdate", () => {
  it("first poll inserts 2 items and records ok status + conditional-GET validators", async () => {
    const { store, calls } = fakeStore();
    const fetcher = vi.fn(async () => documentResponse(PAGE_HTML));

    const result = await runPageFeedUpdate(feedRecord(), fetcher, store);

    expect(result).toEqual({ status: "ok", newItems: 2 });
    expect(calls.inserted).toHaveLength(1);
    expect(calls.successes[0].settingsPatch).toEqual({
      pageStatus: "ok",
      pageEtag: '"v1"',
      pageLastModified: "Wed, 01 Jan 2026 00:00:00 GMT",
    });
    expect(calls.misses).toHaveLength(0);
  });

  it("sends If-None-Match/If-Modified-Since from the stored settings", async () => {
    const { store } = fakeStore();
    const fetcher = vi.fn(async () => ({ status: 304, body: null, contentType: null, etag: null, lastModified: null, finalUrl: PAGE_URL }) as FetchedDocument);

    await runPageFeedUpdate(
      feedRecord({ pageEtag: '"v1"', pageLastModified: "Wed, 01 Jan 2026 00:00:00 GMT" }),
      fetcher,
      store,
    );

    expect(fetcher).toHaveBeenCalledWith(PAGE_URL, {
      etag: '"v1"',
      lastModified: "Wed, 01 Jan 2026 00:00:00 GMT",
    });
  });

  it("re-extracting the same HTML yields 0 new items (hash identity, not position)", async () => {
    const { store, calls } = fakeStore();
    const fetcher = vi.fn(async () => documentResponse(PAGE_HTML));

    const first = await runPageFeedUpdate(feedRecord(), fetcher, store);
    const second = await runPageFeedUpdate(feedRecord({ pageEtag: '"v1"' }), fetcher, store);

    expect(first.newItems).toBe(2);
    expect(second.newItems).toBe(0);
    expect(calls.inserted).toHaveLength(2);
  });

  it("a 304 short-circuits with no re-parse and no inserts, status ok", async () => {
    const { store, calls } = fakeStore();
    const fetcher = vi.fn(async () => ({ status: 304, body: null, contentType: null, etag: null, lastModified: null, finalUrl: PAGE_URL }) as FetchedDocument);

    const result = await runPageFeedUpdate(feedRecord(), fetcher, store);

    expect(result).toEqual({ status: "not-modified", newItems: 0 });
    expect(calls.inserted).toHaveLength(0);
    expect(calls.successes).toHaveLength(1);
    expect(calls.successes[0].settingsPatch).toEqual({ pageStatus: "ok" });
    expect(calls.misses).toHaveLength(0);
  });

  it("a selector miss keeps the last good items and flags the feed error instead of zeroing it", async () => {
    const { store, calls } = fakeStore();
    calls.existingGuids.add("already-there");
    const fetcher = vi.fn(async () => documentResponse(MISS_HTML, '"v2"'));

    const result = await runPageFeedUpdate(feedRecord({ pageEtag: '"v1"' }), fetcher, store);

    expect(result).toEqual({ status: "kept-last-good", newItems: 0 });
    expect(calls.misses).toHaveLength(1);
    expect(calls.misses[0].message).toContain("matched 0 elements");
    expect(calls.successes).toHaveLength(0);
    expect(calls.inserted).toHaveLength(0);
    expect(calls.existingGuids.has("already-there")).toBe(true);
  });

  it("propagates fetch failures so the shared error path can flag the feed", async () => {
    const { store } = fakeStore();
    const fetcher = vi.fn(async () => {
      throw new Error("HTTP 500 fetching page");
    });

    await expect(runPageFeedUpdate(feedRecord(), fetcher, store)).rejects.toThrow("HTTP 500");
  });

  it("pageFeedConditionalState tolerates null/default settings", () => {
    expect(pageFeedConditionalState({ id: "f", pageUrl: "u", pageSelector: "s", settings: {} })).toEqual({
      etag: null,
      lastModified: null,
    });
    expect(pageFeedConditionalState({ id: "f", pageUrl: "u", pageSelector: "s", settings: null })).toEqual({
      etag: null,
      lastModified: null,
    });
  });
});

describe("page-feed guid identity", () => {
  it("matches sha256(pageUrl + '|' + normalized identity + '|' + title) from the real extractor", () => {
    const expected = crypto
      .createHash("sha256")
      .update(`${PAGE_URL}|${normalizeItemIdentity("https://example.com/posts/one")}|First`)
      .digest("hex");
    const guids = extractPageItems(PAGE_HTML, PAGE_URL, SELECTOR).map((i) => i.guid);
    expect(guids).toContain(expected);
  });
});

describe("validatePageFeedInput", () => {
  const valid = { pageUrl: "https://example.com/blog", pageSelector: "article.post" };

  it("accepts a valid payload and defaults nothing extra", async () => {
    const parsed = await validatePageFeedInput(valid);
    expect(parsed.pageUrl).toBe("https://example.com/blog");
  });

  it("rejects unsafe pageUrls (SSRF surface) with a 400 AppError", async () => {
    await expect(validatePageFeedInput({ ...valid, pageUrl: "http://127.0.0.1:6380" })).rejects.toMatchObject({
      statusCode: 400,
    });
    await expect(validatePageFeedInput({ ...valid, pageUrl: "file:///etc/passwd" })).rejects.toBeInstanceOf(AppError);
  });

  it("rejects script-like selectors", async () => {
    await expect(validatePageFeedInput({ ...valid, pageSelector: "<script>alert(1)</script>" })).rejects.toMatchObject({
      statusCode: 400,
    });
    await expect(validatePageFeedInput({ ...valid, pageSelector: "a[href=javascript:alert(1)]" })).rejects.toMatchObject({
      statusCode: 400,
    });
    await expect(validatePageFeedInput({ ...valid, pageSelector: "div[onclick=bad]" })).rejects.toMatchObject({
      statusCode: 400,
    });
  });

  it("rejects selectors longer than 500 characters (zod shape)", async () => {
    await expect(
      validatePageFeedInput({ ...valid, pageSelector: "a".repeat(501) }),
    ).rejects.toMatchObject({ name: "ZodError" });
  });
});
