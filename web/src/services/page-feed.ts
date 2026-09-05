import { z } from "zod";
import { AppError } from "../lib/api/errors.js";
import { assertSafeFeedUrl } from "./feed-fetch.js";
import { decodeBody, extractPageItems, extractPageTitle, fetchDocument, type PageItem } from "./extraction.js";

// Page-feed support: a feed whose "items" are scraped from an HTML page via
// a CSS selector instead of parsed from RSS/Atom. Resilience semantics
// (keep-last-good on selector miss, content-hash identity, conditional GET,
// retry, single-flight) per the v0.4 spike, with patterns adapted from
// RSSHub (MIT).

const SCRIPT_TOKEN_RE = /<\s*script|javascript\s*:|\bon\w+\s*=/i;

const pageFeedSchema = z.object({
  pageUrl: z.string().min(1),
  pageSelector: z.string().min(1).max(500),
  title: z.string().max(500).optional(),
  folderId: z.string().uuid().optional(),
  updateInterval: z.number().min(5).max(1440).optional(),
});

export type PageFeedInput = z.infer<typeof pageFeedSchema>;

export async function validatePageFeedInput(body: unknown): Promise<PageFeedInput> {
  const data = pageFeedSchema.parse(body);
  if (SCRIPT_TOKEN_RE.test(data.pageSelector)) {
    throw new AppError("pageSelector contains disallowed script-like tokens", 400);
  }
  await assertSafeFeedUrl(data.pageUrl);
  return data;
}

// Creation-time verification: fetch the page once through the hardened
// core and prove the selector matches at least one element before the feed
// row is stored.
export async function verifyPageSelector(
  pageUrl: string,
  pageSelector: string,
): Promise<{ items: PageItem[]; documentTitle: string | null }> {
  const doc = await fetchDocument(pageUrl);
  if (doc.status !== 200 || !doc.body) {
    throw new AppError(`Unable to fetch page (HTTP ${doc.status}): ${pageUrl}`, 400);
  }
  const html = decodeBody(doc.body, doc.contentType);
  const items = extractPageItems(html, pageUrl, pageSelector);
  if (items.length === 0) {
    throw new AppError(`Selector matched 0 elements on ${pageUrl}`, 400);
  }
  return { items, documentTitle: extractPageTitle(html) };
}

export interface PageFeedRecord {
  id: string;
  pageUrl: string | null;
  pageSelector: string | null;
  settings: unknown;
}

export interface PageFeedStore {
  insertItems(feedId: string, items: PageItem[], pageUrl: string): Promise<number>;
  markSuccess(feedId: string, settingsPatch: Record<string, unknown>): Promise<void>;
  markSelectorMiss(feedId: string, message: string): Promise<void>;
}

export interface PageFeedConditionalState {
  etag: string | null;
  lastModified: string | null;
}

export function pageFeedConditionalState(feed: PageFeedRecord): PageFeedConditionalState {
  const settings = (feed.settings ?? {}) as Record<string, unknown>;
  const etag = typeof settings.pageEtag === "string" ? settings.pageEtag : null;
  const lastModified = typeof settings.pageLastModified === "string" ? settings.pageLastModified : null;
  return { etag, lastModified };
}

export type PageFeedUpdateStatus = "ok" | "not-modified" | "kept-last-good";

export interface PageFeedUpdateResult {
  status: PageFeedUpdateStatus;
  newItems: number;
}

// The resilient page-feed poll: conditional GET, hash identity upserts, and
// keep-last-good on a selector/list miss (never zero the feed). Network and
// storage are injected so the semantics stay unit-testable without either.
export async function runPageFeedUpdate(
  feed: PageFeedRecord,
  fetchPage: typeof fetchDocument,
  store: PageFeedStore,
): Promise<PageFeedUpdateResult> {
  const { id: feedId, pageUrl, pageSelector } = feed;
  if (!pageUrl || !pageSelector) {
    throw new Error(`Page feed ${feedId} is missing pageUrl or pageSelector`);
  }

  const conditional = pageFeedConditionalState(feed);
  const doc = await fetchPage(pageUrl, {
    etag: conditional.etag,
    lastModified: conditional.lastModified,
  });

  if (doc.status === 304) {
    await store.markSuccess(feedId, {});
    return { status: "not-modified", newItems: 0 };
  }

  if (doc.status !== 200 || !doc.body) {
    throw new Error(`HTTP ${doc.status} fetching page: ${pageUrl}`);
  }

  const html = decodeBody(doc.body, doc.contentType);
  const items = extractPageItems(html, pageUrl, pageSelector);

  if (items.length === 0) {
    await store.markSelectorMiss(feedId, `Selector matched 0 elements on ${pageUrl}`);
    return { status: "kept-last-good", newItems: 0 };
  }

  const inserted = await store.insertItems(feedId, items, pageUrl);
  await store.markSuccess(feedId, {
    pageEtag: doc.etag ?? null,
    pageLastModified: doc.lastModified ?? null,
  });
  return { status: "ok", newItems: inserted };
}
