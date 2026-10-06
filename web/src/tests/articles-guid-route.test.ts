import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));

import { loader as articleListLoader } from "../routes/api/articles/index.js";
import { loader as articleDetailLoader } from "../routes/api/articles/[articleId].js";
import { getDb } from "../lib/api/db.js";

// Contract: the article list and detail payloads expose the publisher
// GUID. Clients key identity on (feedId, guid); a URL is not a safe
// substitute when the real GUID differs, so the rows used here have
// guid !== url and the SELECT must carry articles.guid.

interface SelectCall {
  fields: unknown;
}

function chainable(rows: unknown[]) {
  const q: Record<string, unknown> = {
    then: (
      onFulfilled: (value: unknown) => unknown,
      onRejected: (reason: unknown) => unknown,
    ) => Promise.resolve(rows).then(onFulfilled, onRejected),
  };
  for (const method of ["from", "innerJoin", "leftJoin", "where", "orderBy", "limit", "offset"]) {
    q[method] = () => q;
  }
  return q as never;
}

function makeDb(selectResults: unknown[][]) {
  const selectCalls: SelectCall[] = [];
  let selectIndex = 0;
  const db = {
    select: (fields?: unknown) => {
      selectCalls.push({ fields });
      const rows = selectResults[Math.min(selectIndex, selectResults.length - 1)] ?? [];
      selectIndex++;
      return chainable(rows);
    },
  };
  return { db, selectCalls };
}

async function thrownResponse(promise: Promise<unknown>): Promise<Response> {
  try {
    await promise;
  } catch (error) {
    return error as Response;
  }
  throw new Error("expected loader to throw its Response");
}

const guidRow = {
  id: "a1",
  feedId: "f1",
  guid: "urn:uuid:real-publisher-guid",
  title: "T",
  url: "https://example.com/post/1",
  summary: null,
  content: null,
  author: null,
  publishedAt: null,
  imageUrl: null,
  enclosures: [],
  isRead: null,
  isStarred: null,
  readAt: null,
  feedTitle: "Feed",
  feedFavicon: null,
};

const context = { user: { id: "u1" } };

beforeEach(() => {
  vi.mocked(getDb).mockReset();
});

describe("article payloads expose the publisher guid", () => {
  it("GET /api/articles selects articles.guid and returns it verbatim", async () => {
    const { db, selectCalls } = makeDb([[guidRow], [{ count: 1 }]]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await thrownResponse(
      articleListLoader({
        request: new Request("http://localhost/api/articles?page=1&limit=20"),
        context,
      }),
    );
    const body = (await response.json()) as {
      articles: Array<{ guid: string; url: string }>;
    };

    expect(selectCalls[0]?.fields).toMatchObject({ guid: expect.anything() });
    expect(body.articles).toHaveLength(1);
    expect(body.articles[0].guid).toBe("urn:uuid:real-publisher-guid");
    expect(body.articles[0].guid).not.toBe(body.articles[0].url);
  });

  it("GET /api/articles/:id returns the guid alongside the url", async () => {
    const { db } = makeDb([[guidRow]]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await thrownResponse(
      articleDetailLoader({ params: { articleId: "a1" }, context }),
    );
    const body = (await response.json()) as {
      article: { guid: string; url: string };
    };

    expect(body.article.guid).toBe("urn:uuid:real-publisher-guid");
    expect(body.article.guid).not.toBe(body.article.url);
  });
});
