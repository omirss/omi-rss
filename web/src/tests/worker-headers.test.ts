import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));

// fetchDocument is mocked so the test asserts the WORKER wiring: the
// extract job must pass the feed's stored httpHeaders (loaded via the
// articles→feeds join) through to the document fetch.
vi.mock("../services/extraction.js", () => ({
  fetchDocument: vi.fn(async () => ({
    status: 200,
    body: new TextEncoder().encode("<html><head><title>t</title></head><body><p>enough text to pass readability thresholds and more words here to be safe about it</p></body></html>"),
    contentType: "text/html; charset=utf-8",
    etag: null,
    lastModified: null,
    finalUrl: "http://8.8.8.8/article",
  })),
  decodeBody: vi.fn((bytes: Uint8Array) => new TextDecoder().decode(bytes)),
  extractArticle: vi.fn(() => ({
    title: "t",
    contentHtml: "<p>extracted</p>",
    method: "readability" as const,
  })),
}));

import { getDb } from "../lib/api/db.js";
import { fetchDocument } from "../services/extraction.js";

function fakeDb(article: Record<string, unknown> | []) {
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

describe("processExtractArticle header wiring", () => {
  it("passes the feed's stored httpHeaders to fetchDocument (single join query)", async () => {
    const { processExtractArticle } = await import("../worker.js");
    const { db, updates } = fakeDb({
      id: "a1",
      url: "http://8.8.8.8/article",
      contentExtracted: null,
      httpHeaders: { cookie: "subscriber=token123", "x-key": "v" },
    });
    vi.mocked(getDb).mockResolvedValue(db as never);

    const result = await processExtractArticle("a1");

    expect(result.status).toBe("ok-readability");
    expect(vi.mocked(fetchDocument)).toHaveBeenCalledWith("http://8.8.8.8/article", undefined, {
      cookie: "subscriber=token123",
      "x-key": "v",
    });
    expect(updates).toHaveLength(1);
    expect(updates[0].contentExtracted).toBe("<p>extracted</p>");
  });

  it("passes undefined when the feed has no headers", async () => {
    const { processExtractArticle } = await import("../worker.js");
    const { db } = fakeDb({
      id: "a2",
      url: "http://8.8.8.8/other-article",
      contentExtracted: null,
      httpHeaders: null,
    });
    vi.mocked(getDb).mockResolvedValue(db as never);

    await processExtractArticle("a2");

    expect(vi.mocked(fetchDocument)).toHaveBeenCalledWith("http://8.8.8.8/other-article", undefined, undefined);
  });
});
