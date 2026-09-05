import { describe, it, expect } from "vitest";
import { parseHTML } from "linkedom";
import crypto from "node:crypto";
import {
  decodeBody,
  truncateHtml,
  injectBase,
  fixLazyImages,
  absolutizeUrls,
  sanitizeContentHtml,
  extractArticle,
  extractPageItems,
  extractPageTitle,
  EXTRACTION_LIMITS,
  type ExtractDocument,
} from "./extraction.js";

// Pipeline-stage tests against inline HTML fixtures — no network. Order and
// semantics follow the v0.4 spike (RESULTS.md pipeline is normative).

const LONG_TEXT = "This is a sufficiently long article body paragraph that gives the readability parser something substantial to score. ".repeat(3);

function readableArticlePage(body: string): string {
  return `<!doctype html><html><head><title>Test Page</title></head><body><article><h1>Article Title</h1>${body}</article></body></html>`;
}

describe("charset decoding", () => {
  const latin1Bytes = new Uint8Array([67, 97, 102, 233, 32, 100, 233, 106, 224]); // "Café déjà"

  it("decodes latin-1 bytes from a Content-Type header charset without U+FFFD", () => {
    const text = decodeBody(latin1Bytes, "text/html; charset=ISO-8859-1");
    expect(text).toBe("Café déjà");
    expect(text).not.toContain("\uFFFD");
  });

  it("falls back to a <meta charset> sniff of the first 4KB when the header has none", () => {
    const prefix = new TextEncoder().encode('<html><head><meta charset="windows-1252"></head><body>Caf');
    const bytes = new Uint8Array([...prefix, 233]); // é in windows-1252
    const text = decodeBody(bytes, "text/html");
    expect(text).toContain("Café");
    expect(text).not.toContain("\uFFFD");
  });

  it("defaults to UTF-8 and never throws", () => {
    const text = decodeBody(new TextEncoder().encode("plain ascii"), null);
    expect(text).toBe("plain ascii");
  });
});

describe("size caps", () => {
  it("truncates decoded HTML to the 2MB parse cap", () => {
    const huge = "x".repeat(EXTRACTION_LIMITS.MAX_HTML_CHARS + 100);
    expect(truncateHtml(huge).length).toBe(EXTRACTION_LIMITS.MAX_HTML_CHARS);
    expect(truncateHtml("short")).toBe("short");
  });

  it("caps stored sanitized HTML at 256KB", () => {
    const huge = `<p>${"a".repeat(300 * 1024)}</p>`;
    expect(sanitizeContentHtml(huge).length).toBeLessThanOrEqual(EXTRACTION_LIMITS.MAX_STORED_HTML);
  });
});

describe("base href injection", () => {
  it("injects <base href> into an existing <head>", () => {
    const html = injectBase("<html><head><title>t</title></head><body></body></html>", "https://example.com/post/1");
    expect(html).toMatch(/<head[^>]*><base href="https:\/\/example\.com\/post\/1">/);
  });

  it("creates a head when the document has none", () => {
    const html = injectBase("<html><body><p>x</p></body></html>", "https://example.com/");
    expect(html).toContain('<base href="https://example.com/">');
  });

  it("makes Readability resolve relative image URLs against the page URL", () => {
    const page = readableArticlePage(`<p>${LONG_TEXT}</p><img src="/img/pic.png">`);
    const result = extractArticle(page, "https://example.com/posts/1");
    expect(result.method).toBe("readability");
    expect(result.contentHtml).toContain("https://example.com/img/pic.png");
  });
});

describe("lazy-image fixup", () => {
  function document(html: string): ExtractDocument {
    return parseHTML(html).document as unknown as ExtractDocument;
  }

  it("promotes data-src over a data: placeholder", () => {
    const doc = document('<html><body><img src="data:image/gif;base64,R0lGOD" data-src="/real.jpg"></body></html>');
    fixLazyImages(doc);
    expect([...doc.querySelectorAll("img")][0].getAttribute("src")).toBe("/real.jpg");
  });

  it("promotes data-lazy-src and data-original when data-src is absent", () => {
    const doc = document('<html><body><img data-lazy-src="/lazy.jpg"><img data-original="/orig.jpg"></body></html>');
    fixLazyImages(doc);
    const imgs = [...doc.querySelectorAll("img")];
    expect(imgs[0].getAttribute("src")).toBe("/lazy.jpg");
    expect(imgs[1].getAttribute("src")).toBe("/orig.jpg");
  });

  it("falls back to the last srcset candidate when src is a 1x1 pixel placeholder", () => {
    const doc = document('<html><body><img src="1x1.gif" srcset="/a.png 100w, /b.png 500w"></body></html>');
    fixLazyImages(doc);
    expect([...doc.querySelectorAll("img")][0].getAttribute("src")).toBe("/b.png");
  });

  it("leaves usable src alone", () => {
    const doc = document('<html><body><img src="/fine.jpg" data-src="/other.jpg"></body></html>');
    fixLazyImages(doc);
    expect([...doc.querySelectorAll("img")][0].getAttribute("src")).toBe("/fine.jpg");
  });
});

describe("absolutize + sanitize", () => {
  it("resolves relative src/href against the base URL before sanitize", () => {
    const doc = parseHTML(
      '<html><body><div><a href="/rel/path">link</a><img src="img/pic.png"></div></body></html>',
    ).document as unknown as ExtractDocument;
    const div = doc.querySelector("div")!;
    absolutizeUrls(div, "https://example.com/posts/1");
    expect(div.querySelector("a")!.getAttribute("href")).toBe("https://example.com/rel/path");
    expect(div.querySelector("img")!.getAttribute("src")).toBe("https://example.com/posts/img/pic.png");
  });

  it("strips script/style/iframe/event handlers/javascript: URIs and keeps formatting + imgs", () => {
    const dirty =
      '<p onclick="evil()">text</p><script>alert(1)</script><style>body{}</style>' +
      '<iframe src="https://evil.example"></iframe><a href="javascript:evil()">click</a>' +
      '<b>bold</b><img src="https://example.com/i.png" alt="i">';
    const clean = sanitizeContentHtml(dirty);
    expect(clean).not.toContain("<script");
    expect(clean).not.toContain("onclick");
    expect(clean).not.toContain("javascript:");
    expect(clean).not.toContain("<iframe");
    expect(clean).not.toContain("<style");
    expect(clean).toContain("<b>bold</b>");
    expect(clean).toContain('<img src="https://example.com/i.png"');
  });
});

describe("extraction fallback ladder", () => {
  it("rung 1: Readability wins on a readable article", () => {
    const page = readableArticlePage(`<p>${LONG_TEXT}</p>`);
    const result = extractArticle(page, "https://example.com/posts/1");
    expect(result.method).toBe("readability");
    expect(result.title).toBeTruthy();
    expect(result.contentHtml).toContain("sufficiently long article");
  });

  it("rung 2: site selector seed takes over when Readability output is too thin", () => {
    const page =
      '<html><head><title>m</title></head><body><div><section><p>medium content</p></section></div></body></html>';
    const result = extractArticle(page, "https://medium.com/@user/some-post");
    expect(result.method).toBe("selector");
    expect(result.contentHtml).toContain("medium content");
  });

  it("rung 3: og/meta description becomes an excerpt when no selector matches", () => {
    const page =
      '<html><head><title>Thin</title><meta property="og:description" content="An og excerpt"></head><body><div>thin</div></body></html>';
    const result = extractArticle(page, "https://example.com/thin");
    expect(result.method).toBe("meta");
    expect(result.contentHtml).toContain("An og excerpt");
    expect(result.contentHtml).not.toContain("<script");
  });

  it("rung 1 wins over the site selector when both are available", () => {
    const page = readableArticlePage(`<p>${LONG_TEXT}</p>`);
    const result = extractArticle(page, "https://medium.com/@user/full-post");
    expect(result.method).toBe("readability");
  });
});

describe("page-feed item extraction", () => {
  const pageUrl = "https://example.com/blog";
  const page = `
    <html><head><title>Blog</title></head><body><main>
      <article class="post"><h2><a href="/posts/one">First post</a></h2><p>Body one <a href="/x">ref</a></p></article>
      <article class="post"><h3>Second post</h3><a href="https://other.example/two">read</a><p>Body two</p></article>
      <div class="ad">ignore</div>
    </main></body></html>`;

  it("extracts one item per selector match with absolute links and sanitized innerHTML", () => {
    const items = extractPageItems(page, pageUrl, "article.post");
    expect(items).toHaveLength(2);

    expect(items[0].title).toBe("First post");
    expect(items[0].link).toBe("https://example.com/posts/one");
    expect(items[0].contentHtml).toContain("Body one");
    expect(items[0].contentHtml).toContain('href="https://example.com/x"');

    expect(items[1].title).toBe("Second post");
    expect(items[1].link).toBe("https://other.example/two");
  });

  it("derives stable guids from sha256(pageUrl + '|' + link-or-title)", () => {
    const items = extractPageItems(page, pageUrl, "article.post");
    const expected0 = crypto.createHash("sha256").update(`${pageUrl}|https://example.com/posts/one`).digest("hex");
    const expected1 = crypto.createHash("sha256").update(`${pageUrl}|https://other.example/two`).digest("hex");
    expect(items[0].guid).toBe(expected0);
    expect(items[1].guid).toBe(expected1);

    expect(extractPageItems(page, pageUrl, "article.post").map((i) => i.guid)).toEqual([expected0, expected1]);
  });

  it("treats the matched element itself as the link when the selector matches anchors", () => {
    const anchorPage = `<html><body><ul><li class="item"><a href="/one">One</a></li><li class="item"><a href="/two">Two</a></li></ul></body></html>`;
    const items = extractPageItems(anchorPage, pageUrl, "li.item a");
    expect(items).toHaveLength(2);
    expect(items[0].link).toBe("https://example.com/one");
    expect(items[1].link).toBe("https://example.com/two");
    const expected = crypto.createHash("sha256").update(`${pageUrl}|https://example.com/one`).digest("hex");
    expect(items[0].guid).toBe(expected);
  });

  it("returns an empty list on a selector miss (never invents items)", () => {
    expect(extractPageItems(page, pageUrl, ".does-not-exist")).toEqual([]);
  });

  it("deduplicates repeated guids within one extraction", () => {
    const twice = page.replace("</main>", '<article class="post"><h2><a href="/posts/one">First post</a></h2></article></main>');
    const items = extractPageItems(twice, pageUrl, "article.post");
    expect(items).toHaveLength(2);
  });

  it("extracts the document title", () => {
    expect(extractPageTitle(page)).toBe("Blog");
  });
});
