import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));

import { loader } from "../routes/api/feeds/[feedId].js";
import { getDb } from "../lib/api/db.js";

// GET /api/feeds/:id extraction-stats contract: fullTextEnabled feeds get an
// aggregate over the 200 most recent articles (created_at DESC), others get
// no extractionStats key at all — and no third query.

interface FakeDbOptions {
  feedRows: unknown[];
  statRows: unknown[];
  extractionRows: unknown[];
  fromSources?: unknown[];
}

function fakeDb({ feedRows, statRows, extractionRows, fromSources = [] }: FakeDbOptions) {
  const resultSets = [feedRows, statRows, extractionRows];
  let call = 0;
  const selectQuery = (rows: unknown[]) => {
    const q: Record<string, unknown> = {
      then: (onFulfilled: (value: unknown) => unknown, onRejected: (reason: unknown) => unknown) =>
        Promise.resolve(rows).then(onFulfilled, onRejected),
    };
    for (const method of ["where", "limit", "groupBy", "orderBy"]) {
      q[method] = () => q;
    }
    return q as never;
  };
  const db = {
    select: () => {
      const rows = resultSets[Math.min(call, resultSets.length - 1)] ?? [];
      call += 1;
      return {
        from: (source: unknown) => {
          fromSources.push(source);
          return selectQuery(rows);
        },
      };
    },
  };
  return { db, selectCalls: () => call };
}

// Flattens a drizzle SQL object into readable text: interpolated values
// render as [value] so LIMIT 200 is assertable alongside the literal SQL.
function sqlText(chunk: unknown): string {
  if (chunk === null || chunk === undefined) return "";
  if (typeof chunk === "string" || typeof chunk === "number" || typeof chunk === "boolean") {
    return `[${String(chunk)}]`;
  }
  if (Array.isArray(chunk)) return chunk.map(sqlText).join(" ");
  const obj = chunk as { constructor?: { name: string }; value?: unknown; queryChunks?: unknown[]; name?: unknown };
  const kind = obj.constructor?.name;
  if (kind === "StringChunk") return String(obj.value ?? "");
  if (typeof obj.name === "string") return obj.name;
  if (obj.queryChunks) return obj.queryChunks.map(sqlText).join("");
  return "";
}

const context = { user: { id: "u1" } };

// handleLoader throws the Response (Neutron middleware contract) — catch it
// back out so tests can assert on status and body.
async function runLoader(params: Record<string, string>): Promise<Response> {
  try {
    await loader({ params, context });
    throw new Error("loader resolved instead of throwing a Response");
  } catch (thrown) {
    if (thrown instanceof Response) return thrown;
    throw thrown;
  }
}

beforeEach(() => {
  vi.mocked(getDb).mockReset();
});

describe("GET /api/feeds/:id extractionStats", () => {
  it("aggregates over the 200 most recent articles for full-text feeds", async () => {
    const fromSources: unknown[] = [];
    const { db, selectCalls } = fakeDb({
      feedRows: [{ id: "f1", userId: "u1", fullTextEnabled: true }],
      statRows: [{ totalArticles: "10", unreadArticles: "4" }],
      extractionRows: [{ scanned: "200", extracted: "180", failed: "15", pending: "5" }],
      fromSources,
    });
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await runLoader({ feedId: "f1" });
    const body = (await response.json()) as {
      feed: { fullTextEnabled: boolean };
      stats: { totalArticles: number; unreadArticles: number };
      extractionStats: { scanned: number; extracted: number; failed: number; pending: number; windowLimit: number };
    };

    expect(response.status).toBe(200);
    expect(body.feed.fullTextEnabled).toBe(true);
    expect(body.stats.totalArticles).toBe(10);
    expect(body.extractionStats).toEqual({ scanned: 200, extracted: 180, failed: 15, pending: 5, windowLimit: 200 });
    expect(selectCalls()).toBe(3);

    const extractionSql = sqlText(fromSources[2]);
    expect(extractionSql).toContain("SELECT content_extracted FROM");
    expect(extractionSql).toContain("feed_id");
    expect(extractionSql).toContain("ORDER BY");
    expect(extractionSql).toContain("created_at DESC");
    expect(extractionSql).toContain("LIMIT [200]");
  });

  it("omits extractionStats (and the query) when full text is off", async () => {
    const fromSources: unknown[] = [];
    const { db, selectCalls } = fakeDb({
      feedRows: [{ id: "f1", userId: "u1", fullTextEnabled: false }],
      statRows: [{ totalArticles: "3", unreadArticles: "1" }],
      extractionRows: [],
      fromSources,
    });
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await runLoader({ feedId: "f1" });
    const body = (await response.json()) as { extractionStats?: unknown };

    expect(response.status).toBe(200);
    expect("extractionStats" in body).toBe(false);
    expect(selectCalls()).toBe(2);
  });

  it("returns 404 for unknown feeds", async () => {
    const { db } = fakeDb({ feedRows: [], statRows: [], extractionRows: [] });
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await runLoader({ feedId: "missing" });

    expect(response.status).toBe(404);
  });
});
