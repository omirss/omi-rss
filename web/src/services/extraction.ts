import crypto from "node:crypto";
import { Readability } from "@mozilla/readability";
import { parseHTML } from "linkedom";
import sanitizeHtml from "sanitize-html";
import { AppError } from "../lib/api/errors.js";
import { assertSafeFeedUrl, assertRedirectLocation } from "./feed-fetch.js";
import { withHostGate } from "./host-gate.js";
import { sameSiteHost } from "./site-host.js";
import { findExtractionRules } from "./extraction-rules.js";

// v0.4.0 extraction engine. Pipeline (normative, from the v0.4 spike):
// fetch → charset decode (header → meta-sniff → utf-8) → 2MB truncate →
// inject <base href> → lazy-img fixup → linkedom parse → Readability →
// fallback ladder (site selector seed → og/meta description excerpt) →
// absolutize URLs → sanitize-html → store (capped 256KB).
// Sanitization is sanitize-html server-side; DOMPurify silently no-ops on
// linkedom windows, so it stays client-side only (ReaderView).
// Resilience patterns (retry codes, per-URL memoization, keep-last-good,
// single-flight) adapted from RSSHub (MIT).

const EXTRACT_USER_AGENT = "omi-rss/0.4.1 (+https://omirss.com)";
const FETCH_TIMEOUT_MS = 10000;
const MAX_REDIRECT_HOPS = 3;
const MAX_BODY_BYTES = 2 * 1024 * 1024;
const MAX_HTML_CHARS = 2 * 1024 * 1024;
const MAX_STORED_HTML = 256 * 1024;
const RETRYABLE_STATUSES = new Set([408, 429, 500, 502, 503, 504]);
const RETRY_ATTEMPTS = 2;
const RETRY_DELAY_MS = 1000;
const READABILITY_MIN_TEXT = 100;
const MAX_PAGE_ITEMS = 100;

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

// Minimal structural types so linkedom documents pass without importing
// lib.dom's incompatible Document/Element into every signature.
export interface ExtractElement {
  tagName: string;
  textContent: string | null;
  innerHTML: string;
  getAttribute(name: string): string | null;
  setAttribute(name: string, value: string): unknown;
  removeAttribute(name: string): unknown;
  hasAttribute(name: string): boolean;
  querySelectorAll(selector: string): Iterable<ExtractElement>;
  querySelector(selector: string): ExtractElement | null;
}

export interface ExtractDocument {
  querySelectorAll(selector: string): Iterable<ExtractElement>;
  querySelector(selector: string): ExtractElement | null;
}

export function decodeBody(bytes: Uint8Array, contentType: string | null): string {
  const headerCharset = contentType?.match(/charset\s*=\s*["']?([\w-]+)/i)?.[1];
  const head = new TextDecoder("utf-8").decode(bytes.slice(0, 4096));
  const metaCharset = head.match(/<meta[^>]+charset\s*=\s*["']?([\w-]+)/i)?.[1];
  const labels = [headerCharset, metaCharset, "utf-8"];
  for (const label of labels) {
    if (!label) continue;
    try {
      return new TextDecoder(label.toLowerCase()).decode(bytes);
    } catch {
      // Unknown charset label — fall to the next rung.
    }
  }
  return new TextDecoder("utf-8").decode(bytes);
}

export function truncateHtml(html: string): string {
  return html.length <= MAX_HTML_CHARS ? html : html.slice(0, MAX_HTML_CHARS);
}

function escapeAttr(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
}

function escapeText(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

// linkedom's document.baseURI is null, so Readability's relative-URI fixing
// no-ops unless a <base href> exists in the parsed source (spike Q7).
// The anchor requires <head> exactly or <head ...> (a bare prefix match
// would also hit <header>), and matches inside HTML comments are skipped.
const HEAD_OPEN_RE = /<head(\s[^>]*)?>/gi;

function findHeadOpenIndex(html: string): number {
  HEAD_OPEN_RE.lastIndex = 0;
  let match: RegExpExecArray | null;
  while ((match = HEAD_OPEN_RE.exec(html)) !== null) {
    const prefix = html.slice(0, match.index);
    const commentOpen = prefix.lastIndexOf("<!--");
    if (commentOpen === -1 || prefix.lastIndexOf("-->") > commentOpen) {
      return match.index;
    }
  }
  return -1;
}

export function injectBase(html: string, baseUrl: string): string {
  const tag = `<base href="${escapeAttr(baseUrl)}">`;
  const headIndex = findHeadOpenIndex(html);
  if (headIndex !== -1) {
    const match = /<head(\s[^>]*)?>/i.exec(html.slice(headIndex));
    const insertAt = headIndex + (match ? match[0].length : 0);
    return html.slice(0, insertAt) + tag + html.slice(insertAt);
  }
  if (/<html(\s[^>]*)?>/i.test(html)) {
    return html.replace(/<html(\s[^>]*)?>/i, (htmlTag) => htmlTag + `<head>${tag}</head>`);
  }
  return `<head>${tag}</head>` + html;
}

// Placeholders: data-URI images (anchored to ^data:image) and well-known
// placeholder names matched as whole path tokens (so "pixel" matches
// "/1x1/pixel.gif" but not "/img/superpixel-collage.jpg").
const LAZY_PLACEHOLDER_SRC = /^data:image|(?:^|\/)[^/]*\b(?:1x1|pixel|transparent)\b/i;
const LAZY_SRC_ATTRIBUTES = ["data-src", "data-lazy-src", "data-original"];

// Picks the srcset candidate with the largest declared width descriptor
// (candidates without one count as 0), not simply the last listed.
export function largestSrcsetCandidate(srcset: string): string | null {
  let best: { url: string; width: number } | null = null;
  for (const candidate of srcset.split(",")) {
    const trimmed = candidate.trim();
    if (!trimmed) continue;
    const parts = trimmed.split(/\s+/);
    const url = parts[0];
    if (!url) continue;
    let width = 0;
    for (const descriptor of parts.slice(1)) {
      const widthMatch = /^(\d+)w$/.exec(descriptor);
      if (widthMatch) {
        width = parseInt(widthMatch[1], 10);
        break;
      }
    }
    if (!best || width > best.width) {
      best = { url, width };
    }
  }
  return best?.url ?? null;
}

// Spike Q4a: promote lazy-load placeholders to real src before Readability.
export function fixLazyImages(document: ExtractDocument): void {
  for (const img of document.querySelectorAll("img")) {
    let src = img.getAttribute("src") ?? "";
    const usable = (value: string | null) => !!value && !LAZY_PLACEHOLDER_SRC.test(value);
    if (!usable(src)) {
      const promoted = LAZY_SRC_ATTRIBUTES.map((attr) => img.getAttribute(attr)).find(usable);
      if (promoted) {
        src = promoted;
        img.setAttribute("src", src);
      }
    }
    if (!usable(src) && img.hasAttribute("srcset")) {
      const candidate = largestSrcsetCandidate(img.getAttribute("srcset") ?? "");
      if (candidate !== null && usable(candidate)) {
        img.setAttribute("src", candidate);
      }
    }
  }
}

// Runs before sanitize so relative src/href survive as absolute URLs; the
// sanitizer has no DOMPurify-style hooks to do this later.
export function absolutizeUrls(root: ExtractElement, baseUrl: string): void {
  for (const el of root.querySelectorAll("a[href], img[src], source[src]")) {
    const attr = el.tagName.toLowerCase() === "a" ? "href" : "src";
    const raw = el.getAttribute(attr);
    if (!raw) continue;
    try {
      el.setAttribute(attr, new URL(raw, baseUrl).href);
    } catch {
      el.removeAttribute(attr);
    }
  }
}

const SANITIZE_OPTIONS: sanitizeHtml.IOptions = {
  allowedTags: [
    "p", "br", "hr", "h1", "h2", "h3", "h4", "h5", "h6",
    "blockquote", "pre", "code",
    "em", "i", "strong", "b", "u", "s", "del", "ins", "sub", "sup", "small", "mark", "abbr", "cite", "q",
    "a", "img", "figure", "figcaption",
    "ul", "ol", "li", "dl", "dt", "dd",
    "table", "thead", "tbody", "tfoot", "tr", "th", "td", "caption",
    "span", "div", "time",
  ],
  allowedAttributes: {
    a: ["href", "title"],
    img: ["src", "alt", "title", "width", "height", "loading"],
    time: ["datetime"],
    th: ["colspan", "rowspan"],
    td: ["colspan", "rowspan"],
  },
  allowedSchemes: ["http", "https", "mailto"],
  allowedSchemesByTag: { img: ["http", "https", "data"] },
  allowProtocolRelative: false,
};

export function sanitizeContentHtml(html: string): string {
  let clean = sanitizeHtml(html, SANITIZE_OPTIONS);
  if (clean.length > MAX_STORED_HTML) {
    clean = sanitizeHtml(clean.slice(0, MAX_STORED_HTML), SANITIZE_OPTIONS).slice(0, MAX_STORED_HTML);
  }
  return clean;
}

function parseDocument(html: string, baseUrl: string): ExtractDocument {
  const prepared = injectBase(truncateHtml(html), baseUrl);
  return parseHTML(prepared).document as unknown as ExtractDocument;
}

function documentTitle(document: ExtractDocument): string | null {
  const title = document.querySelector("title")?.textContent?.trim();
  return title || null;
}

function metaDescription(document: ExtractDocument): string | null {
  const og = document.querySelector('meta[property="og:description"]')?.getAttribute("content");
  const standard = document.querySelector('meta[name="description"]')?.getAttribute("content");
  return (og || standard || "").trim() || null;
}

function plainTextLength(text: string): number {
  return text.replace(/\s+/g, " ").trim().length;
}

function safeHostname(url: string): string | null {
  try {
    return new URL(url).hostname;
  } catch {
    return null;
  }
}

export type ExtractionMethod = "readability" | "selector" | "meta";

export interface ExtractionResult {
  title: string | null;
  contentHtml: string;
  method: ExtractionMethod;
}

// Fallback ladder: Readability → per-site selector seed → og/meta
// description excerpt (spike Q4b). Readability mutates (and can wreck) its
// input document, so the selector/meta rungs re-parse fresh source.
export function extractArticle(html: string, url: string): ExtractionResult {
  const prepared = injectBase(truncateHtml(html), url);

  let readabilityTitle: string | null = null;
  try {
    const doc = parseHTML(prepared).document as unknown as ExtractDocument;
    fixLazyImages(doc);
    const parsed = new Readability(doc as unknown as globalThis.Document).parse();
    if (parsed) {
      readabilityTitle = parsed.title?.trim() || null;
      const text = parsed.textContent ?? parsed.content ?? "";
      if (parsed.content && plainTextLength(text) >= READABILITY_MIN_TEXT) {
        return { title: readabilityTitle, contentHtml: sanitizeContentHtml(parsed.content), method: "readability" };
      }
    }
  } catch {
    // Fall through to the selector seed.
  }

  const document = parseHTML(prepared).document as unknown as ExtractDocument;
  fixLazyImages(document);

  const hostname = safeHostname(url);
  const rules = hostname ? findExtractionRules(hostname) : null;
  if (rules?.contentSelector) {
    const contentElement = document.querySelector(rules.contentSelector);
    if (contentElement) {
      absolutizeUrls(contentElement, url);
      const seededTitle = rules.titleSelector
        ? document.querySelector(rules.titleSelector)?.textContent?.trim() || null
        : null;
      return {
        title: seededTitle ?? readabilityTitle ?? documentTitle(document),
        contentHtml: sanitizeContentHtml(contentElement.innerHTML),
        method: "selector",
      };
    }
  }

  const description = metaDescription(document);
  if (description) {
    return {
      title: readabilityTitle ?? documentTitle(document),
      contentHtml: sanitizeContentHtml(`<p>${escapeText(description)}</p>`),
      method: "meta",
    };
  }

  return { title: readabilityTitle ?? documentTitle(document), contentHtml: "", method: "meta" };
}

export interface PageItem {
  guid: string;
  title: string;
  link: string | null;
  contentHtml: string;
}

function firstHttpLink(element: ExtractElement, baseUrl: string): string | null {
  const candidates: (ExtractElement | null)[] = [
    element.tagName.toLowerCase() === "a" ? element : null,
    ...element.querySelectorAll("a[href]"),
  ];
  for (const anchor of candidates) {
    if (!anchor) continue;
    const href = anchor.getAttribute("href");
    if (!href || href.startsWith("#")) continue;
    try {
      const resolved = new URL(href, baseUrl);
      if (resolved.protocol === "http:" || resolved.protocol === "https:") {
        return resolved.href;
      }
    } catch {
      // Unresolvable href — try the next anchor.
    }
  }
  return null;
}

function elementHeadingTitle(element: ExtractElement): string | null {
  for (const heading of element.querySelectorAll("h1, h2, h3, h4, h5, h6")) {
    const text = heading.textContent?.replace(/\s+/g, " ").trim();
    if (text) return text;
  }
  const link = element.querySelector("a[href]")?.textContent?.replace(/\s+/g, " ").trim();
  if (link) return link;
  const text = element.textContent?.replace(/\s+/g, " ").trim();
  return text ? text.slice(0, 200) : null;
}

// Item identity normalization: strips utm_*/fbclid query params and
// trailing slashes so the same article URL yields the same guid regardless
// of tracking parameters. Non-URL values (titles) only lose trailing
// slashes. v0.4.1: the title is always part of the hash — two cards linking
// the same URL with different titles are distinct items (one-time effect:
// existing page feeds re-insert their items once).
export function normalizeItemIdentity(value: string): string {
  try {
    const url = new URL(value);
    if (url.protocol === "http:" || url.protocol === "https:") {
      for (const key of [...url.searchParams.keys()]) {
        if (key.startsWith("utm_") || key === "fbclid") {
          url.searchParams.delete(key);
        }
      }
      if (url.pathname !== "/") {
        url.pathname = url.pathname.replace(/\/+$/, "");
      }
      return url.toString();
    }
  } catch {
    // Not an absolute URL — plain string normalization.
  }
  return value.replace(/\/+$/, "");
}

function pageItemGuid(pageUrl: string, link: string | null, title: string): string {
  const identity = normalizeItemIdentity(link ?? title);
  return crypto.createHash("sha256").update(`${pageUrl}|${identity}|${title}`).digest("hex");
}

function collectPageItems(document: ExtractDocument, pageUrl: string, selector: string): PageItem[] {
  const items: PageItem[] = [];
  const seen = new Set<string>();

  for (const element of document.querySelectorAll(selector)) {
    const link = firstHttpLink(element, pageUrl);
    const title = elementHeadingTitle(element) ?? "Untitled";
    const guid = pageItemGuid(pageUrl, link, title);
    if (seen.has(guid)) continue;
    seen.add(guid);
    absolutizeUrls(element, pageUrl);
    items.push({ guid, title, link, contentHtml: sanitizeContentHtml(element.innerHTML) });
    if (items.length >= MAX_PAGE_ITEMS) break;
  }

  return items;
}

// Page-feed item extraction: every selector match becomes an item; identity
// is sha256(pageUrl + "|" + normalize(link-or-title) + "|" + title) so DOM
// reshuffles never duplicate or lose items (spike Q5; identity revised
// v0.4.1).
export function extractPageItems(html: string, pageUrl: string, selector: string): PageItem[] {
  return collectPageItems(parseDocument(html, pageUrl), pageUrl, selector);
}

// Single-parse variant for page-feed creation: items and document title
// from one linkedom pass (the creation path used to parse twice).
export function extractPageData(
  html: string,
  pageUrl: string,
  selector: string,
): { items: PageItem[]; title: string | null } {
  const document = parseDocument(html, pageUrl);
  return { items: collectPageItems(document, pageUrl, selector), title: documentTitle(document) };
}

export function extractPageTitle(html: string): string | null {
  return documentTitle(parseHTML(truncateHtml(html)).document as unknown as ExtractDocument);
}

async function readCapped(body: ReadableStream<Uint8Array> | null, cap: number): Promise<Uint8Array | null> {
  if (!body) return null;
  const parts: Uint8Array[] = [];
  let total = 0;
  for await (const chunk of body as unknown as AsyncIterable<Uint8Array>) {
    if (total + chunk.length > cap) {
      parts.push(chunk.slice(0, cap - total));
      total = cap;
      break;
    }
    parts.push(chunk);
    total += chunk.length;
    if (total === cap) break;
  }
  const buffer = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    buffer.set(part, offset);
    offset += part.length;
  }
  return buffer;
}

export interface FetchedDocument {
  status: number;
  body: Uint8Array | null;
  contentType: string | null;
  etag: string | null;
  lastModified: string | null;
  finalUrl: string;
}

export interface ConditionalGetHeaders {
  etag?: string | null;
  lastModified?: string | null;
}

// Hardened document fetch for article extraction and page-feed polls:
// assertSafeFeedUrl up front (article URLs are feed data = SSRF surface),
// per-host semaphore on EVERY request including each redirect hop (A→B
// joins B's gate, not just A's), UA, 10s timeout, 2MB body cap, manual
// redirects with every hop re-validated, retry 408/429/5xx ×2 with 1s
// backoff, and conditional GET (If-None-Match/If-Modified-Since) for
// page-feeds. Response bodies on non-read paths (redirects, non-OK
// statuses, retry candidates) are cancelled so sockets release promptly.
export async function fetchDocument(
  url: string,
  conditional?: ConditionalGetHeaders,
  customHeaders?: Record<string, string>,
): Promise<FetchedDocument> {
  await assertSafeFeedUrl(url);

  let lastError: unknown = new Error(`Failed to fetch document: ${url}`);

  for (let attempt = 0; attempt <= RETRY_ATTEMPTS; attempt++) {
    if (attempt > 0) {
      await sleep(RETRY_DELAY_MS);
    }
    try {
      const result = await fetchDocumentWithRedirects(url, conditional, customHeaders);
      if (RETRYABLE_STATUSES.has(result.status) && attempt < RETRY_ATTEMPTS) {
        lastError = new Error(`HTTP ${result.status} fetching document: ${url}`);
        continue;
      }
      return result;
    } catch (error) {
      if (error instanceof AppError) {
        throw error;
      }
      lastError = error;
    }
  }
  throw lastError instanceof Error ? lastError : new Error(`Failed to fetch document: ${url}`);
}

async function discardBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // Already consumed or locked — nothing left to release.
  }
}

async function fetchWithTimeout(
  url: string,
  headers: Record<string, string>,
): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    return await fetch(url, { headers, redirect: "manual", signal: controller.signal });
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      throw new Error(`Document fetch timed out after ${FETCH_TIMEOUT_MS}ms: ${url}`);
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchDocumentWithRedirects(
  url: string,
  conditional?: ConditionalGetHeaders,
  customHeaders?: Record<string, string>,
): Promise<FetchedDocument> {
  let currentUrl = url;
  // Bring-your-own-subscription headers survive redirect hops only while
  // the destination stays on the ORIGINAL request's site (sameSiteHost:
  // naive registrable-domain match, exact for IP literals) — cookies and
  // authorization are site-scoped, so a cross-site hop drops them
  // instead of leaking the owner's credentials to the redirect target.
  let currentCustomHeaders = customHeaders;

  for (let hop = 0; hop <= MAX_REDIRECT_HOPS; hop++) {
    const headers: Record<string, string> = {
      "User-Agent": EXTRACT_USER_AGENT,
      Accept: "text/html, application/xhtml+xml, */*",
    };
    if (conditional?.etag) headers["If-None-Match"] = conditional.etag;
    if (conditional?.lastModified) headers["If-Modified-Since"] = conditional.lastModified;
    Object.assign(headers, currentCustomHeaders);

    // Each hop re-enters the host gate for its DESTINATION host.
    const response = await withHostGate(currentUrl, () => fetchWithTimeout(currentUrl, headers));

    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get("location");
      await discardBody(response);
      if (!location) {
        return emptyResult(response.status, currentUrl);
      }
      if (hop === MAX_REDIRECT_HOPS) {
        throw new AppError(`Blocked feed URL (exceeded ${MAX_REDIRECT_HOPS} redirect hops): ${url}`, 400);
      }
      const nextUrl = await assertRedirectLocation(currentUrl, location);
      if (currentCustomHeaders && !sameSiteHost(url, nextUrl)) {
        currentCustomHeaders = undefined;
      }
      currentUrl = nextUrl;
      continue;
    }

    if (response.ok || response.status === 304) {
      const body = await readCapped(response.body, MAX_BODY_BYTES);
      return {
        status: response.status,
        body,
        contentType: response.headers.get("content-type"),
        etag: response.headers.get("etag"),
        lastModified: response.headers.get("last-modified"),
        finalUrl: currentUrl,
      };
    }

    await discardBody(response);
    return emptyResult(response.status, currentUrl);
  }

  throw new AppError(`Blocked feed URL (exceeded ${MAX_REDIRECT_HOPS} redirect hops): ${url}`, 400);
}

function emptyResult(status: number, finalUrl: string): FetchedDocument {
  return { status, body: null, contentType: null, etag: null, lastModified: null, finalUrl };
}

export const EXTRACTION_LIMITS = {
  MAX_BODY_BYTES,
  MAX_HTML_CHARS,
  MAX_STORED_HTML,
  MAX_PAGE_ITEMS,
} as const;
