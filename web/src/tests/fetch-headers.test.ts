import { describe, it, expect, beforeAll, afterAll, afterEach } from "vitest";
import http from "node:http";
import type { IncomingMessage, ServerResponse } from "node:http";
import { fetchFeedXml } from "../services/feed-fetch.js";
import { fetchDocument } from "../services/extraction.js";

// Worker header wiring at the fetch layer, against real local HTTP servers
// (the pinned transport is node:http, not global fetch): a feed's
// bring-your-own-subscription headers ride on every request to that feed's
// origin, and survive redirects only while the hop stays on the exact same
// origin. ALLOW_PRIVATE_FEED_URLS lets the 127.0.0.1 listeners through.

const XML = `<?xml version="1.0"?><rss version="2.0"><channel><title>t</title></channel></rss>`;
const HTML = "<html><head><title>t</title></head><body><p>body text</p></body></html>";

type Handler = (req: IncomingMessage, res: ServerResponse, path: string) => void;

interface CapturedRequest {
  url: string;
  headers: IncomingMessage["headers"];
}

interface TestServer {
  origin: string;
  requests: CapturedRequest[];
  route(handler: Handler): void;
}

const closers: Array<() => Promise<void>> = [];

function startServer(): Promise<TestServer> {
  const requests: CapturedRequest[] = [];
  let handler: Handler = (_req, res) => {
    res.writeHead(404);
    res.end();
  };
  const server = http.createServer((req, res) => {
    requests.push({ url: req.url ?? "/", headers: req.headers });
    handler(req, res, req.url ?? "/");
  });
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address() as { address: string; port: number };
      closers.push(() => new Promise<void>((done) => server.close(() => done())));
      resolve({
        origin: `http://127.0.0.1:${port}`,
        requests,
        route: (next) => {
          handler = next;
        },
      });
    });
  });
}

let serverA: TestServer;
let serverB: TestServer;

beforeAll(async () => {
  serverA = await startServer();
  serverB = await startServer();
  process.env.ALLOW_PRIVATE_FEED_URLS = "true";
});

afterAll(async () => {
  delete process.env.ALLOW_PRIVATE_FEED_URLS;
  await Promise.all(closers.map((close) => close()));
});

afterEach(() => {
  serverA.requests.length = 0;
  serverB.requests.length = 0;
});

const COOKIE = { Cookie: "subscriber=token123" };

function serveXml(_req: IncomingMessage, res: ServerResponse) {
  res.writeHead(200, { "content-type": "text/xml" });
  res.end(XML);
}

function serveHtml(_req: IncomingMessage, res: ServerResponse) {
  res.writeHead(200, { "content-type": "text/html" });
  res.end(HTML);
}

describe("fetchFeedXml custom headers", () => {
  it("sends the feed's headers with the request", async () => {
    serverA.route(serveXml);

    const body = await fetchFeedXml(`${serverA.origin}/feed.xml`, COOKIE);

    expect(body).toBe(XML);
    expect(serverA.requests).toHaveLength(1);
    expect(serverA.requests[0].headers.cookie).toBe("subscriber=token123");
    expect(serverA.requests[0].headers["user-agent"]).toContain("omi-rss");
  });

  it("preserves custom headers across same-origin redirect hops", async () => {
    serverA.route((_req, res, path) => {
      if (path === "/feed.xml") {
        res.writeHead(302, { location: `${serverA.origin}/feed-real.xml` });
        res.end("redirect body that must not be read");
        return;
      }
      serveXml(_req, res);
    });

    await fetchFeedXml(`${serverA.origin}/feed.xml`, COOKIE);

    expect(serverA.requests.map((r) => r.url)).toEqual(["/feed.xml", "/feed-real.xml"]);
    expect(serverA.requests[0].headers.cookie).toBe("subscriber=token123");
    expect(serverA.requests[1].headers.cookie).toBe("subscriber=token123");
  });

  it("drops custom headers on cross-origin redirect hops", async () => {
    serverA.route((_req, res) => {
      res.writeHead(302, { location: `${serverB.origin}/feed-real.xml` });
      res.end();
    });
    serverB.route(serveXml);

    await fetchFeedXml(`${serverA.origin}/feed.xml`, COOKIE);

    expect(serverA.requests[0].headers.cookie).toBe("subscriber=token123");
    expect(serverB.requests[0].url).toBe("/feed-real.xml");
    expect(serverB.requests[0].headers.cookie).toBeUndefined();
  });

  it("does not re-send dropped headers after returning from a cross-origin hop", async () => {
    serverA.route((_req, res, path) => {
      if (path === "/a.xml") {
        res.writeHead(302, { location: `${serverB.origin}/b.xml` });
        res.end();
        return;
      }
      serveXml(_req, res);
    });
    serverB.route((_req, res) => {
      res.writeHead(302, { location: `${serverA.origin}/c.xml` });
      res.end();
    });

    await fetchFeedXml(`${serverA.origin}/a.xml`, COOKIE);

    expect(serverA.requests.map((r) => r.url)).toEqual(["/a.xml", "/c.xml"]);
    expect(serverB.requests.map((r) => r.url)).toEqual(["/b.xml"]);
    expect(serverA.requests[1].headers.cookie).toBeUndefined();
  });

  it("sends no custom headers when none are stored", async () => {
    serverA.route(serveXml);

    await fetchFeedXml(`${serverA.origin}/feed.xml`, undefined);

    expect(serverA.requests[0].headers.cookie).toBeUndefined();
  });
});

describe("fetchDocument custom headers", () => {
  it("sends the feed's headers with the article fetch", async () => {
    serverA.route(serveHtml);

    const doc = await fetchDocument(`${serverA.origin}/article`, undefined, COOKIE);

    expect(doc.status).toBe(200);
    expect(serverA.requests).toHaveLength(1);
    expect(serverA.requests[0].headers.cookie).toBe("subscriber=token123");
    expect(serverA.requests[0].headers["user-agent"]).toContain("omi-rss");
  });

  it("custom headers override the defaults (user-supplied User-Agent wins)", async () => {
    serverA.route(serveHtml);

    await fetchDocument(`${serverA.origin}/article`, undefined, { "User-Agent": "Custom/1.0" });

    expect(serverA.requests[0].headers["user-agent"]).toBe("Custom/1.0");
  });

  it("preserves custom headers across same-origin redirects, drops them cross-origin", async () => {
    serverA.route((_req, res, path) => {
      if (path === "/article") {
        res.writeHead(301, { location: `${serverA.origin}/article-real` });
        res.end();
        return;
      }
      if (path === "/article2") {
        res.writeHead(301, { location: `${serverB.origin}/article-real` });
        res.end();
        return;
      }
      serveHtml(_req, res);
    });
    serverB.route(serveHtml);

    await fetchDocument(`${serverA.origin}/article`, undefined, COOKIE);
    await fetchDocument(`${serverA.origin}/article2`, undefined, COOKIE);

    expect(serverA.requests).toHaveLength(3);
    expect(serverA.requests[1].headers.cookie).toBe("subscriber=token123");
    expect(serverB.requests[0].headers.cookie).toBeUndefined();
  });

  it("keeps conditional GET headers alongside custom headers", async () => {
    serverA.route(serveHtml);

    await fetchDocument(`${serverA.origin}/article`, { etag: '"v1"' }, COOKIE);

    expect(serverA.requests[0].headers["if-none-match"]).toBe('"v1"');
    expect(serverA.requests[0].headers.cookie).toBe("subscriber=token123");
  });
});
