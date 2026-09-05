import { describe, it, expect, vi, afterEach } from "vitest";
import { parseHTML } from "linkedom";
import crypto from "node:crypto";
import {
  decodeBody,
  truncateHtml,
  injectBase,
  fixLazyImages,
  largestSrcsetCandidate,
  normalizeItemIdentity,
  absolutizeUrls,
  sanitizeContentHtml,
  extractArticle,
  extractPageItems,
  extractPageTitle,
  fetchDocument,
  EXTRACTION_LIMITS,
  type ExtractDocument,
} from "./extraction.js";

vi.mock("./host-gate.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./host-gate.js")>();
  const withHostGate = vi.fn((url: string, fn: () => Promise<unknown>) => fn());
  return { ...actual, withHostGate };
});

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

  it("injects into <head> with attributes but never into <header>", () => {
    const attributed = injectBase('<html><head lang="en"><title>t</title></head><body><header>h</header></body></html>', "https://example.com/");
    expect(attributed).toContain('<head lang="en"><base href="https://example.com/">');
    expect(attributed).not.toContain('<header><base');

    const headerOnly = injectBase("<html><body><header>site header</header></body></html>", "https://example.com/");
    expect(headerOnly).toContain('<head><base href="https://example.com/"></head>');
    expect(headerOnly).not.toContain('<header><base');
  });

  it("skips <head> matches inside HTML comments", () => {
    const html = injectBase(
      '<html><body><!-- <head> old template --><main>x</main></body></html>',
      "https://example.com/",
    );
    expect(html).toContain('<html><head><base href="https://example.com/"></head>');
    expect(html).not.toContain("old template --><base");
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

  it("falls back to the largest srcset width descriptor when src is a 1x1 pixel placeholder", () => {
    const doc = document('<html><body><img src="1x1.gif" srcset="/a.png 100w, /b.png 500w"></body></html>');
    fixLazyImages(doc);
    expect([...doc.querySelectorAll("img")][0].getAttribute("src")).toBe("/b.png");
  });

  it("picks the largest declared width, not the last listed candidate", () => {
    const doc = document('<html><body><img src="pixel.gif" srcset="/small.png 100w, /big.png 900w, /mid.png 400w"></body></html>');
    fixLazyImages(doc);
    expect([...doc.querySelectorAll("img")][0].getAttribute("src")).toBe("/big.png");
  });

  it("does not treat placeholder-name substrings inside real filenames as placeholders", () => {
    const doc = document('<html><body><img src="/img/superpixel-collage.jpg" data-src="/real.jpg"></body></html>');
    fixLazyImages(doc);
    expect([...doc.querySelectorAll("img")][0].getAttribute("src")).toBe("/img/superpixel-collage.jpg");
  });

  it("leaves usable src alone", () => {
    const doc = document('<html><body><img src="/fine.jpg" data-src="/other.jpg"></body></html>');
    fixLazyImages(doc);
    expect([...doc.querySelectorAll("img")][0].getAttribute("src")).toBe("/fine.jpg");
  });
});

describe("largestSrcsetCandidate", () => {
  it("picks the largest width descriptor", () => {
    expect(largestSrcsetCandidate("/a.png 100w, /b.png 500w, /c.png 200w")).toBe("/b.png");
  });

  it("treats candidates without a width descriptor as zero-width", () => {
    expect(largestSrcsetCandidate("/a.png, /b.png 400w")).toBe("/b.png");
    expect(largestSrcsetCandidate("/a.png, /b.png")).toBe("/a.png");
  });

  it("returns null for empty input", () => {
    expect(largestSrcsetCandidate("")).toBeNull();
    expect(largestSrcsetCandidate(" , ")).toBeNull();
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

  function guidFor(link: string, title: string): string {
    return crypto
      .createHash("sha256")
      .update(`${pageUrl}|${normalizeItemIdentity(link)}|${title}`)
      .digest("hex");
  }

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

  it("derives stable guids from sha256(pageUrl + '|' + normalized identity + '|' + title)", () => {
    const items = extractPageItems(page, pageUrl, "article.post");
    expect(items[0].guid).toBe(guidFor("https://example.com/posts/one", "First post"));
    expect(items[1].guid).toBe(guidFor("https://other.example/two", "Second post"));

    expect(extractPageItems(page, pageUrl, "article.post").map((i) => i.guid)).toEqual([
      items[0].guid,
      items[1].guid,
    ]);
  });

  it("treats the matched element itself as the link when the selector matches anchors", () => {
    const anchorPage = `<html><body><ul><li class="item"><a href="/one">One</a></li><li class="item"><a href="/two">Two</a></li></ul></body></html>`;
    const items = extractPageItems(anchorPage, pageUrl, "li.item a");
    expect(items).toHaveLength(2);
    expect(items[0].link).toBe("https://example.com/one");
    expect(items[1].link).toBe("https://example.com/two");
    expect(items[0].guid).toBe(guidFor("https://example.com/one", "One"));
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

describe("page-feed guid normalization (v0.4.1 identity)", () => {
  const pageUrl = "https://example.com/blog";

  function card(href: string, title: string): string {
    return `<html><body><article class="post"><h2><a href="${href}">${title}</a></h2></article></body></html>`;
  }

  const guidOf = (html: string): string | undefined => extractPageItems(html, pageUrl, "article.post")[0]?.guid;

  it("strips utm_* and fbclid params so tracked and clean URLs share identity", () => {
    expect(guidOf(card("/a?utm_source=rss&utm_medium=feed", "T"))).toBe(guidOf(card("/a", "T")));
    expect(guidOf(card("/a?fbclid=abc123", "T"))).toBe(guidOf(card("/a", "T")));
    expect(guidOf(card("/a?utm_campaign=x&keep=1", "T"))).toBe(guidOf(card("/a?keep=1", "T")));
  });

  it("strips trailing slashes so /a and /a/ share identity", () => {
    expect(guidOf(card("/a/", "T"))).toBe(guidOf(card("/a", "T")));
    expect(guidOf(card("/a//", "T"))).toBe(guidOf(card("/a", "T")));
  });

  it("keeps the title in the hash: same link with different titles are distinct items", () => {
    expect(guidOf(card("/a", "One title"))).not.toBe(guidOf(card("/a", "Another title")));
  });

  it("different links stay distinct even with identical titles", () => {
    expect(guidOf(card("/a", "T"))).not.toBe(guidOf(card("/b", "T")));
  });

  it("collapses utm-vs-clean duplicates within one extraction", () => {
    const both = `<html><body><main>
      <article class="post"><h2><a href="/a?utm_source=x">T</a></h2></article>
      <article class="post"><h2><a href="/a">T</a></h2></article>
    </main></body></html>`;
    expect(extractPageItems(both, pageUrl, "article.post")).toHaveLength(1);
  });

  it("normalizeItemIdentity handles URLs, plain strings and non-http schemes", () => {
    expect(normalizeItemIdentity("https://x.example/a?utm_term=y&id=2")).toBe("https://x.example/a?id=2");
    expect(normalizeItemIdentity("https://x.example")).toBe("https://x.example/");
    expect(normalizeItemIdentity("https://x.example/")).toBe("https://x.example/");
    expect(normalizeItemIdentity("Some title/")).toBe("Some title");
    expect(normalizeItemIdentity("mailto:a@b.example")).toBe("mailto:a@b.example");
  });
});

describe("fetchDocument resource handling", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
  });

  interface FakeResponseSpec {
    status: number;
    headers?: Record<string, string>;
    body?: string;
  }

  function cancellableResponse(spec: FakeResponseSpec): { response: Response; cancelled: () => boolean } {
    let cancelled = false;
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        if (spec.body !== undefined) {
          controller.enqueue(new TextEncoder().encode(spec.body));
        }
        controller.close();
      },
      cancel() {
        cancelled = true;
      },
    });
    return {
      response: new Response(stream, { status: spec.status, headers: spec.headers }),
      cancelled: () => cancelled,
    };
  }

  it("cancels the response body on redirect hops", async () => {
    const redirect = cancellableResponse({
      status: 302,
      headers: { location: "https://93.184.215.35/b" },
      body: "redirect junk",
    });
    const final = cancellableResponse({ status: 200, body: "<html>x</html>" });
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(redirect.response)
      .mockResolvedValueOnce(final.response);
    vi.stubGlobal("fetch", fetchImpl);

    const doc = await fetchDocument("https://93.184.216.34/a");
    expect(doc.status).toBe(200);
    expect(doc.finalUrl).toBe("https://93.184.215.35/b");
    expect(new TextDecoder().decode(doc.body!)).toBe("<html>x</html>");
    expect(redirect.cancelled()).toBe(true);
    expect(final.cancelled()).toBe(false);
  });

  it("cancels the response body on non-OK statuses", async () => {
    const notFound = cancellableResponse({ status: 404, body: "not here" });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(notFound.response));

    const doc = await fetchDocument("https://93.184.216.34/a");
    expect(doc.status).toBe(404);
    expect(doc.body).toBeNull();
    expect(notFound.cancelled()).toBe(true);
  });

  it("cancels retryable-status bodies between retry attempts", async () => {
    const retryable = cancellableResponse({ status: 503, body: "busy" });
    const ok = cancellableResponse({ status: 200, body: "<html>ok</html>" });
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(retryable.response)
      .mockResolvedValueOnce(ok.response);
    vi.stubGlobal("fetch", fetchImpl);

    const doc = await fetchDocument("https://93.184.216.34/a");
    expect(doc.status).toBe(200);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(retryable.cancelled()).toBe(true);
  });

  it("re-enters the host gate for each redirect hop's destination host", async () => {
    const { withHostGate } = await import("./host-gate.js");
    vi.mocked(withHostGate).mockClear();

    const redirect = cancellableResponse({
      status: 301,
      headers: { location: "https://93.184.215.35/b" },
    });
    const final = cancellableResponse({ status: 200, body: "<html>x</html>" });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce(redirect.response).mockResolvedValueOnce(final.response));

    await fetchDocument("https://93.184.216.34/a");

    const gatedUrls = vi.mocked(withHostGate).mock.calls.map(([url]) => url as string);
    expect(gatedUrls).toEqual(["https://93.184.216.34/a", "https://93.184.215.35/b"]);
  });
});
