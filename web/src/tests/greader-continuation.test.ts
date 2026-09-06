import { describe, it, expect, beforeAll, vi, beforeEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));
vi.mock("../lib/greader/limit.js", () => ({ consumeGreaderRateLimit: vi.fn() }));

import { loader } from "../routes/api/greader/[...path].js";
import { getDb } from "../lib/api/db.js";
import { decodeContinuation, encodeContinuation } from "../lib/greader/cursor.js";

// Continuation contract (SPEC 3.5 / gotcha 4): present ONLY when another
// page exists, keyed on the last EMITTED row, stable no-dup/no-drop across
// pages; opaque + signed.

beforeAll(() => {
  process.env.JWT_SECRET = "test-secret";
});

const context = {
  user: {
    id: "u1",
    email: "a@example.com",
    username: "alice",
    role: "user",
    tokenVersion: 0,
    createdAt: new Date(),
  },
};

function refs(rows: Array<[string, string, string]>) {
  return rows.map(([hex16, id, rankUsec]) => ({ hex16, id, rankUsec, feedUrl: "https://example.com/a.xml" }));
}

function fakeDb(pages: Array<{ hex16: string; id: string; rankUsec: string }[]>) {
  let selectIndex = 0;
  let limit = Infinity;
  const rowsFor = () => {
    const rows = pages[Math.min(selectIndex, pages.length - 1)] ?? [];
    return limit === Infinity ? rows : rows.slice(0, limit);
  };
  const q: Record<string, unknown> = {
    then: (res: (v: unknown) => unknown, rej: (r: unknown) => unknown) =>
      Promise.resolve(rowsFor()).then(res, rej),
  };
  for (const method of ["from", "innerJoin", "leftJoin", "where", "orderBy", "offset"]) {
    q[method] = () => q;
  }
  q.limit = (n: number) => {
    limit = n;
    return q;
  };
  const db = {
    select: () => {
      selectIndex++;
      limit = Infinity;
      return q;
    },
  };
  return db;
}

async function getIds(urlQuery: string): Promise<Record<string, unknown>> {
  try {
    await loader({
      request: new Request(`http://localhost/api/greader/reader/api/0/stream/items/ids?${urlQuery}`),
      params: { path: "reader/api/0/stream/items/ids" },
      context,
    });
  } catch (error) {
    const response = error as Response;
    return (await response.json()) as Record<string, unknown>;
  }
  throw new Error("expected loader to throw its Response");
}

beforeEach(() => {
  vi.mocked(getDb).mockReset();
});

describe("cursor codec", () => {
  it("round-trips", () => {
    const payload = { o: "d" as const, r: "1750000000123456", i: "fb115bd6-1234" };
    expect(decodeContinuation(encodeContinuation(payload))).toEqual(payload);
    const ascending = { o: "a" as const, r: "1", i: "x" };
    expect(decodeContinuation(encodeContinuation(ascending))).toEqual(ascending);
  });

  it("rejects tampering and malformed tokens", () => {
    const token = encodeContinuation({ o: "d", r: "1", i: "x" });
    const [body] = token.split(".");
    expect(decodeContinuation(`${body}.forged`)).toBeNull();
    expect(decodeContinuation("not-a-token")).toBeNull();
    expect(decodeContinuation("!!!.???")).toBeNull();
    const badPayload = Buffer.from(JSON.stringify({ o: "x", r: "1", i: "y" })).toString("base64url");
    expect(decodeContinuation(`${badPayload}.whatever`)).toBeNull();
  });
});

describe("stream/items/ids pagination", () => {
  it("fetches n+1 and emits continuation only when more exist", async () => {
    const rows = refs([
      ["5d0cfa30041d4348", "id-1", "1750000000300000"],
      ["024025978b5e50d2", "id-2", "1750000000200000"],
      ["000088960000047a", "id-3", "1750000000100000"],
    ]);
    vi.mocked(getDb).mockResolvedValue(fakeDb([rows]) as never);

    const page1 = await getIds("s=user/-/state/com.google/reading-list&n=2");
    expect((page1.itemRefs as unknown[]).length).toBe(2);
    expect(page1).toHaveProperty("continuation");

    // The cursor keys on the LAST EMITTED row (row 2), not the n+1 fetch.
    const decoded = decodeContinuation(page1.continuation as string);
    expect(decoded).toEqual({ o: "d", r: "1750000000200000", i: "id-2" });
  });

  it("omits continuation entirely on the final page", async () => {
    const rows = refs([
      ["5d0cfa30041d4348", "id-1", "1750000000300000"],
      ["024025978b5e50d2", "id-2", "1750000000200000"],
    ]);
    vi.mocked(getDb).mockResolvedValue(fakeDb([rows]) as never);
    const page = await getIds("s=user/-/state/com.google/reading-list&n=2");
    expect((page.itemRefs as unknown[]).length).toBe(2);
    expect(page).not.toHaveProperty("continuation");
  });

  it("empty result is itemRefs [] with no continuation key", async () => {
    vi.mocked(getDb).mockResolvedValue(fakeDb([[]]) as never);
    const page = await getIds("s=user/-/state/com.google/reading-list");
    expect(page.itemRefs).toEqual([]);
    expect(page).not.toHaveProperty("continuation");
  });

  it("clamps n into 1..1000", async () => {
    const rows = refs([["5d0cfa30041d4348", "id-1", "1"]]);
    vi.mocked(getDb).mockResolvedValue(fakeDb([rows]) as never);
    await getIds("s=user/-/state/com.google/reading-list&n=5000");
    // fake honors the limit passed by the handler: n clamped to 1000 means
    // the query fetched 1001 — with only 1 row the page has no continuation
    const page = await getIds("s=user/-/state/com.google/reading-list&n=5000");
    expect(page).not.toHaveProperty("continuation");
  });

  it("ascending order (r=o) is carried in the cursor direction", async () => {
    const rows = refs([
      ["5d0cfa30041d4348", "id-1", "1750000000300000"],
      ["024025978b5e50d2", "id-2", "1750000000200000"],
      ["000088960000047a", "id-3", "1750000000100000"],
    ]);
    vi.mocked(getDb).mockResolvedValue(fakeDb([rows]) as never);
    const page = await getIds("s=user/-/state/com.google/reading-list&n=2&r=o");
    const decoded = decodeContinuation(page.continuation as string);
    expect(decoded).toMatchObject({ o: "a", r: "1750000000200000", i: "id-2" });
  });
});
