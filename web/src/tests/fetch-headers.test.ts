import { describe, it, expect, vi, afterEach } from "vitest";
import { fetchFeedXml } from "../services/feed-fetch.js";
import { fetchDocument } from "../services/extraction.js";

// Worker header wiring at the fetch layer: a feed's bring-your-own-
// subscription headers ride on every request to that feed's origin, and
// survive redirects only while the hop stays on the original host.
// Fixture-style: a fake global fetch captures init.headers per request.
// Literal-IP URLs skip DNS (SSRF pre-check passes without mocking it).

const XML = `<?xml version="1.0"?><rss version="2.0"><channel><title>t</title></channel></rss>`;
const HTML = "<html><head><title>t</title></head><body><p>body text</p></body></html>";

interface CapturedRequest {
  url: string;
  headers: Record<string, string>;
}

function xmlResponse(): Response {
  return new Response(XML, { status: 200, headers: { "content-type": "text/xml" } });
}

function htmlResponse(): Response {
  return new Response(HTML, { status: 200, headers: { "content-type": "text/html" } });
}

function redirectResponse(location: string): Response {
  return new Response(null, { status: 302, headers: { location } });
}

function stubFetch(handler: (url: string) => Response): CapturedRequest[] {
  const captured: CapturedRequest[] = [];
  vi.stubGlobal("fetch", async (input: string | URL, init?: { headers?: Record<string, string> }) => {
    const url = String(input);
    captured.push({ url, headers: { ...(init?.headers ?? {}) } });
    return handler(url);
  });
  return captured;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

const COOKIE = { Cookie: "subscriber=token123" };

describe("fetchFeedXml custom headers", () => {
  it("sends the feed's headers with the request", async () => {
    const captured = stubFetch(() => xmlResponse());

    const body = await fetchFeedXml("http://8.8.8.8/feed.xml", COOKIE);

    expect(body).toBe(XML);
    expect(captured).toHaveLength(1);
    expect(captured[0].headers.Cookie).toBe("subscriber=token123");
    expect(captured[0].headers["User-Agent"]).toContain("omi-rss");
  });

  it("preserves custom headers across same-host redirect hops", async () => {
    const captured = stubFetch((url) =>
      url === "http://8.8.8.8/feed.xml"
        ? redirectResponse("http://8.8.8.8/feed-real.xml")
        : xmlResponse(),
    );

    await fetchFeedXml("http://8.8.8.8/feed.xml", COOKIE);

    expect(captured).toHaveLength(2);
    expect(captured[0].headers.Cookie).toBe("subscriber=token123");
    expect(captured[1].url).toBe("http://8.8.8.8/feed-real.xml");
    expect(captured[1].headers.Cookie).toBe("subscriber=token123");
  });

  it("drops custom headers on cross-host redirect hops", async () => {
    const captured = stubFetch((url) =>
      url === "http://8.8.8.8/feed.xml"
        ? redirectResponse("http://9.9.9.9/feed-real.xml")
        : xmlResponse(),
    );

    await fetchFeedXml("http://8.8.8.8/feed.xml", COOKIE);

    expect(captured).toHaveLength(2);
    expect(captured[0].headers.Cookie).toBe("subscriber=token123");
    expect(captured[1].url).toBe("http://9.9.9.9/feed-real.xml");
    expect(captured[1].headers.Cookie).toBeUndefined();
  });

  it("does not re-send dropped headers after returning from a cross-host hop", async () => {
    const captured = stubFetch((url) => {
      if (url === "http://8.8.8.8/a.xml") return redirectResponse("http://9.9.9.9/b.xml");
      if (url === "http://9.9.9.9/b.xml") return redirectResponse("http://8.8.8.8/c.xml");
      return xmlResponse();
    });

    await fetchFeedXml("http://8.8.8.8/a.xml", COOKIE);

    expect(captured.map((c) => c.url)).toEqual([
      "http://8.8.8.8/a.xml",
      "http://9.9.9.9/b.xml",
      "http://8.8.8.8/c.xml",
    ]);
    expect(captured[2].headers.Cookie).toBeUndefined();
  });

  it("sends no custom headers when none are stored", async () => {
    const captured = stubFetch(() => xmlResponse());

    await fetchFeedXml("http://8.8.8.8/feed.xml", undefined);

    expect(captured[0].headers.Cookie).toBeUndefined();
  });
});

describe("fetchDocument custom headers", () => {
  it("sends the feed's headers with the article fetch", async () => {
    const captured = stubFetch(() => htmlResponse());

    const doc = await fetchDocument("http://8.8.8.8/article", undefined, COOKIE);

    expect(doc.status).toBe(200);
    expect(captured).toHaveLength(1);
    expect(captured[0].headers.Cookie).toBe("subscriber=token123");
    expect(captured[0].headers["User-Agent"]).toContain("omi-rss");
  });

  it("custom headers override the defaults (user-supplied User-Agent wins)", async () => {
    const captured = stubFetch(() => htmlResponse());

    await fetchDocument("http://8.8.8.8/article", undefined, { "User-Agent": "Custom/1.0" });

    expect(captured[0].headers["User-Agent"]).toBe("Custom/1.0");
  });

  it("preserves custom headers across same-host redirects, drops them cross-host", async () => {
    const captured = stubFetch((url) => {
      if (url === "http://8.8.8.8/article") return redirectResponse("http://8.8.8.8/article-real");
      if (url === "http://8.8.8.8/article2") return redirectResponse("http://9.9.9.9/article-real");
      return htmlResponse();
    });

    await fetchDocument("http://8.8.8.8/article", undefined, COOKIE);
    await fetchDocument("http://8.8.8.8/article2", undefined, COOKIE);

    expect(captured).toHaveLength(4);
    expect(captured[1].headers.Cookie).toBe("subscriber=token123");
    expect(captured[3].headers.Cookie).toBeUndefined();
  });

  it("keeps conditional GET headers alongside custom headers", async () => {
    const captured = stubFetch(() => htmlResponse());

    await fetchDocument("http://8.8.8.8/article", { etag: '"v1"' }, COOKIE);

    expect(captured[0].headers["If-None-Match"]).toBe('"v1"');
    expect(captured[0].headers.Cookie).toBe("subscriber=token123");
  });
});
