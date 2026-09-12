import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { EventEmitter } from "node:events";
import http from "node:http";
import type { RequestOptions } from "node:https";

vi.mock("node:dns/promises", () => ({
  lookup: vi.fn(async (hostname: string) => {
    const records: Record<string, string[]> = {
      "pin.example": ["93.184.216.34"],
      "private.example": ["10.0.0.5"],
    };
    if (!(hostname in records)) {
      throw new Error(`getaddrinfo ENOTFOUND ${hostname}`);
    }
    return [{ address: records[hostname][0], family: 4 }];
  }),
}));

vi.mock("node:https", () => ({ request: vi.fn() }));
vi.mock("node:http", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:http")>();
  const request = vi.fn((...args: Parameters<typeof actual.request>) => actual.request(...args));
  return { ...actual, request };
});

import { fetchPinned } from "../services/feed-fetch.js";
import { request as httpsRequest } from "node:https";
import { lookup } from "node:dns/promises";

// fetchPinned is the SSRF core: the DNS answer used for validation is the
// SAME address the transport connects to (no re-resolution at connect
// time), TLS SNI/cert identity and the Host header keep the original
// hostname, and the body is capped with a whole-request deadline.

interface FakeReq extends EventEmitter {
  end: ReturnType<typeof vi.fn>;
  destroy: (error?: Error) => void;
}

function fakeTransport(status: number, body: string) {
  const calls: RequestOptions[] = [];
  vi.mocked(httpsRequest).mockImplementation(((options: RequestOptions, callback: (res: EventEmitter) => void) => {
    calls.push(options);
    const req = new EventEmitter() as FakeReq;
    req.end = vi.fn(() => {
      const res = new EventEmitter() as EventEmitter & { statusCode: number; headers: Record<string, string> };
      res.statusCode = status;
      res.headers = { "content-type": "text/xml" };
      callback(res);
      res.emit("data", Buffer.from(body));
      res.emit("end");
    });
    req.destroy = (error?: Error) => {
      if (error) req.emit("error", error);
    };
    return req;
  }) as never);
  return calls;
}

beforeEach(() => {
  vi.clearAllMocks();
  delete process.env.ALLOW_PRIVATE_FEED_URLS;
});

afterEach(() => {
  delete process.env.ALLOW_PRIVATE_FEED_URLS;
});

describe("fetchPinned transport pinning", () => {
  it("connects to the validated address, not the hostname, keeping SNI and Host on the original name", async () => {
    const calls = fakeTransport(200, "<rss/>");

    const response = await fetchPinned("https://pin.example/feed.xml", { timeoutMs: 1000, maxBytes: 1024 });

    expect(response.status).toBe(200);
    expect(response.body?.toString()).toBe("<rss/>");
    expect(calls).toHaveLength(1);
    expect(calls[0].host).toBe("93.184.216.34");
    expect(calls[0].servername).toBe("pin.example");
    expect((calls[0].headers as Record<string, string>).Host).toBe("pin.example");
    expect(calls[0].path).toBe("/feed.xml");
    expect(typeof calls[0].checkServerIdentity).toBe("function");
    expect(vi.mocked(lookup)).toHaveBeenCalledWith("pin.example", { all: true });
  });

  it("rejects before connecting when DNS resolves to a private range", async () => {
    await expect(
      fetchPinned("https://private.example/feed.xml", { timeoutMs: 1000, maxBytes: 1024 }),
    ).rejects.toThrow(/loopback, private or link-local/);
    expect(httpsRequest).not.toHaveBeenCalled();
  });

  it("rejects embedded credentials", async () => {
    await expect(
      fetchPinned("https://user:secret@pin.example/feed.xml", { timeoutMs: 1000, maxBytes: 1024 }),
    ).rejects.toThrow(/embedded credentials/);
    expect(httpsRequest).not.toHaveBeenCalled();
  });
});

describe("fetchPinned against a local listener (dev bypass)", () => {
  const closers: Array<() => Promise<void>> = [];

  function startServer(
    handler: (req: http.IncomingMessage, res: http.ServerResponse) => void,
  ): Promise<string> {
    const server = http.createServer(handler);
    return new Promise((resolve) => {
      server.listen(0, "127.0.0.1", () => {
        const { port } = server.address() as { address: string; port: number };
        closers.push(
          () =>
            new Promise<void>((done) => {
              server.closeAllConnections();
              server.close(() => done());
            }),
        );
        resolve(`http://127.0.0.1:${port}`);
      });
    });
  }

  afterEach(async () => {
    await Promise.all(closers.splice(0).map((close) => close()));
  });

  it("sends the Host header with the original port", async () => {
    process.env.ALLOW_PRIVATE_FEED_URLS = "true";
    let seenHost: string | undefined;
    const origin = await startServer((req, res) => {
      seenHost = req.headers.host;
      res.writeHead(200, { "content-type": "text/xml" });
      res.end("<rss/>");
    });

    await fetchPinned(`${origin}/feed.xml`, { timeoutMs: 2000, maxBytes: 1024 });

    expect(seenHost).toBe(origin.replace("http://", ""));
  });

  it("fails the request when the body exceeds maxBytes without truncation", async () => {
    process.env.ALLOW_PRIVATE_FEED_URLS = "true";
    const origin = await startServer((_req, res) => {
      res.writeHead(200, { "content-type": "text/xml" });
      res.end(Buffer.alloc(64 * 1024, "x"));
    });

    await expect(
      fetchPinned(`${origin}/big.xml`, { timeoutMs: 2000, maxBytes: 1024 }),
    ).rejects.toThrow(/exceeded 1024 bytes/);
  });

  it("truncates the body at maxBytes when truncation is allowed", async () => {
    process.env.ALLOW_PRIVATE_FEED_URLS = "true";
    const origin = await startServer((_req, res) => {
      res.writeHead(200, { "content-type": "text/html" });
      res.end(Buffer.alloc(64 * 1024, "x"));
    });

    const response = await fetchPinned(`${origin}/big.html`, {
      timeoutMs: 2000,
      maxBytes: 1024,
      truncateOnOversize: true,
    });

    expect(response.body?.length).toBe(1024);
  });

  it("applies the deadline across headers and body (stalling body rejects)", async () => {
    process.env.ALLOW_PRIVATE_FEED_URLS = "true";
    const origin = await startServer((_req, res) => {
      res.writeHead(200, { "content-type": "text/html" });
      res.write("<html>");
    });

    await expect(
      fetchPinned(`${origin}/stall`, { timeoutMs: 100, maxBytes: 1024 }),
    ).rejects.toThrow(/timed out/i);
  });

  it("destroys the connection on readBody-excluded statuses instead of reading", async () => {
    process.env.ALLOW_PRIVATE_FEED_URLS = "true";
    let closedEarly = false;
    const origin = await startServer((_req, res) => {
      res.writeHead(404);
      res.on("close", () => {
        if (!res.writableEnded) closedEarly = true;
      });
      res.write("junk");
    });

    const response = await fetchPinned(`${origin}/missing`, {
      timeoutMs: 2000,
      maxBytes: 1024,
      readBody: (status) => status < 300,
    });

    expect(response.status).toBe(404);
    expect(response.body).toBeNull();
    await new Promise((resolve) => setTimeout(resolve, 100));
    expect(closedEarly).toBe(true);
  });
});
