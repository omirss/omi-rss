import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));

import { feedDiscoveryService } from "./discovery.js";
import { getDb } from "../lib/api/db.js";

// OPML export/import contract: page feeds do not round-trip as RSS xmlUrl
// outlines, folder hierarchy nests (no synthetic "Uncategorized", no
// merging same-name folders), and customTitle is the exported name.

function makeDb(selectResults: unknown[][]) {
  let selectIndex = 0;
  const query = (rows: unknown[]) => {
    const q: Record<string, unknown> = {
      then: (onFulfilled: (value: unknown) => unknown, onRejected: (reason: unknown) => unknown) =>
        Promise.resolve(rows).then(onFulfilled, onRejected),
    };
    for (const method of ["from", "where"]) {
      q[method] = () => q;
    }
    return q as never;
  };
  return {
    select: () => {
      const rows = selectResults[Math.min(selectIndex, selectResults.length - 1)] ?? [];
      selectIndex++;
      return query(rows);
    },
  } as never;
}

const RSS_FEED = {
  id: "f1",
  userId: "u1",
  folderId: null,
  url: "https://rss.example.com/feed.xml",
  title: "Rss Feed",
  siteUrl: "https://rss.example.com",
  sourceType: "rss",
  customTitle: null,
};

const PAGE_FEED = {
  id: "f2",
  userId: "u1",
  folderId: "folder-1",
  url: "https://page.example.com/blog",
  title: "Page Feed",
  siteUrl: "https://page.example.com",
  sourceType: "page",
  customTitle: null,
};

const FOLDERS = [{ id: "folder-1", name: "Scraped", parentId: null }];

beforeEach(() => {
  vi.mocked(getDb).mockReset();
});

describe("exportOPML", () => {
  it("includes rss feeds and excludes page feeds", async () => {
    vi.mocked(getDb).mockResolvedValue(makeDb([[RSS_FEED, PAGE_FEED], FOLDERS]));

    const opml = await feedDiscoveryService.exportOPML("u1");

    expect(opml).toContain("https://rss.example.com/feed.xml");
    expect(opml).toContain('type="rss"');
    expect(opml).not.toContain("page.example.com");
    expect(opml).not.toContain("Page Feed");
  });

  it("root feeds sit directly in body; empty folders are still exported without feeds", async () => {
    vi.mocked(getDb).mockResolvedValue(makeDb([[RSS_FEED, PAGE_FEED], FOLDERS]));

    const opml = await feedDiscoveryService.exportOPML("u1");

    // The page feed was the folder's only member: the folder exports with
    // no feed outlines inside, and the root feed is not wrapped in any
    // synthetic "Uncategorized" folder.
    expect(opml).not.toContain("Uncategorized");
    expect(opml).toContain('<outline text="Scraped" title="Scraped">');
  });

  it("nests folders by id (never merges same-name folders) and exports customTitle", async () => {
    const feeds = [
      { ...RSS_FEED, id: "f3", folderId: "A", url: "https://a.example/feed", customTitle: "My Custom Name" },
      { ...RSS_FEED, id: "f4", folderId: "B1", url: "https://b.example/feed", customTitle: null, title: "B Feed" },
      { ...RSS_FEED, id: "f5", folderId: null, url: "https://root.example/feed", title: "Root Feed" },
    ];
    const folders = [
      { id: "A", name: "Tech", parentId: null },
      { id: "B", name: "Tech", parentId: null }, // same NAME, different branch
      { id: "B1", name: "Deep", parentId: "B" },
    ];
    vi.mocked(getDb).mockResolvedValue(makeDb([feeds, folders]));

    const opml = await feedDiscoveryService.exportOPML("u1");

    expect(opml).toContain('text="My Custom Name"');
    expect(opml.indexOf('text="Tech"')).toBeLessThan(opml.indexOf('text="Deep"'));
    expect(opml.indexOf('text="Deep"')).toBeLessThan(opml.indexOf('text="B Feed"'));
    // Both "Tech" folders export (no name-keyed merging).
    expect(opml.match(/text="Tech"/g)).toHaveLength(2);
    expect(opml.indexOf('text="Root Feed"')).toBeLessThan(opml.indexOf('text="Tech"'));
  });

  it("treats folders with a dangling parentId as roots instead of dropping them", async () => {
    const folders = [{ id: "orphan", name: "Orphan", parentId: "missing-parent" }];
    vi.mocked(getDb).mockResolvedValue(makeDb([[], folders]));

    const opml = await feedDiscoveryService.exportOPML("u1");

    expect(opml).toContain('text="Orphan"');
  });
});

describe("importOPML parse (hierarchy)", () => {
  function importDb() {
    const inserted: Array<Record<string, unknown>> = [];
    const selectResults: unknown[][] = [[]];
    const query = (rows: unknown[]) => {
      const q: Record<string, unknown> = {
        then: (onFulfilled: (value: unknown) => unknown, onRejected: (reason: unknown) => unknown) =>
          Promise.resolve(rows).then(onFulfilled, onRejected),
      };
      for (const method of ["from", "where"]) {
        q[method] = () => q;
      }
      return q as never;
    };
    const txLike = {
      select: () => query(selectResults[selectResults.length - 1] ?? []),
      insert: () => ({
        values: (values: Record<string, unknown> | Array<Record<string, unknown>>) => {
          const rows = Array.isArray(values) ? values : [values];
          const finish = {
            returning: async () => {
              inserted.push(...rows);
              return rows.map((_, i) => ({ id: `row-${inserted.length}-${i}` }));
            },
          };
          return {
            ...finish,
            onConflictDoNothing: () => finish,
          };
        },
      }),
      transaction: async (fn: (sp: unknown) => Promise<unknown>) => fn(txLike),
    };
    const db = {
      select: () => query([]),
      transaction: async (fn: (tx: unknown) => Promise<unknown>) => fn(txLike),
    };
    return { db, inserted };
  }

  const NESTED_OPML = `<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head><title>export</title></head>
  <body>
    <outline text="Tech" title="Tech">
      <outline text="Deep" title="Deep">
        <outline type="rss" text="B Feed" title="B Feed" xmlUrl="https://b.example/feed" />
      </outline>
      <outline type="rss" text="A Feed" title="A Feed" xmlUrl="https://a.example/feed" />
    </outline>
    <outline type="rss" text="Root Feed" title="Root Feed" xmlUrl="https://root.example/feed" />
  </body>
</opml>`;

  it("keeps folder hierarchy and reuses folders by (parent, name)", async () => {
    process.env.ALLOW_PRIVATE_FEED_URLS = "true";
    try {
      const { db, inserted } = importDb();
      vi.mocked(getDb).mockResolvedValue(db as never);

      const outcome = await feedDiscoveryService.importOPML("u1", NESTED_OPML);

      expect(outcome.imported).toBe(3);
      // feeds carry their resolved folderId (root feed: undefined)
      const bFeed = inserted.find((row) => row.url === "https://b.example/feed");
      const rootFeed = inserted.find((row) => row.url === "https://root.example/feed");
      expect((bFeed as { folderId?: string }).folderId).toBeTruthy();
      expect((rootFeed as { folderId?: string }).folderId).toBeUndefined();
    } finally {
      delete process.env.ALLOW_PRIVATE_FEED_URLS;
    }
  });

  it("rejects OPML with a DOCTYPE (entity expansion surface)", async () => {
    process.env.ALLOW_PRIVATE_FEED_URLS = "true";
    try {
      const { db } = importDb();
      vi.mocked(getDb).mockResolvedValue(db as never);

      await expect(
        feedDiscoveryService.importOPML("u1", `<!DOCTYPE opml [<!ENTITY x "y">]><opml><body/></opml>`),
      ).rejects.toThrow(/DOCTYPE/);
    } finally {
      delete process.env.ALLOW_PRIVATE_FEED_URLS;
    }
  });

  it("a failing chunk fails independently (savepoint) while earlier chunks import", async () => {
    process.env.ALLOW_PRIVATE_FEED_URLS = "true";
    try {
      const { db, inserted } = importDb();
      // Chunk 2's insert rejects; chunk 1 must still count and "commit".
      let calls = 0;
      const txLike = {
        select: () => queryOf([]),
        insert: () => ({
          values: (values: Array<Record<string, unknown>>) => ({
            onConflictDoNothing: () => ({
              returning: async () => {
                calls++;
                if (calls === 2) throw new Error("chunk 2 poison");
                inserted.push(values as never);
                return values.map(() => ({ id: "new" }));
              },
            }),
          }),
        }),
        transaction: async (fn: (sp: unknown) => Promise<unknown>) => fn(txLike),
      };
      const withFailingChunk = {
        ...db,
        transaction: async (fn: (tx: unknown) => Promise<unknown>) => fn(txLike),
      };
      vi.mocked(getDb).mockResolvedValue(withFailingChunk as never);

      // 150 valid feeds: chunk 1 (100) succeeds, chunk 2 (50) fails.
      const entries = Array.from({ length: 150 }, (_, i) => ({
        url: `https://feed-${i}.example/rss`,
        title: `Feed ${i}`,
      }));
      const opml = `<?xml version="1.0"?><opml version="2.0"><body>${entries
        .map((e) => `<outline type="rss" text="${e.title}" xmlUrl="${e.url}" />`)
        .join("")}</body></opml>`;

      const outcome = await feedDiscoveryService.importOPML("u1", opml);

      expect(outcome.imported).toBe(100);
      expect(outcome.failed).toBe(50);
    } finally {
      delete process.env.ALLOW_PRIVATE_FEED_URLS;
    }
  });

  function queryOf(rows: unknown[]) {
    const q: Record<string, unknown> = {
      then: (onFulfilled: (value: unknown) => unknown, onRejected: (reason: unknown) => unknown) =>
        Promise.resolve(rows).then(onFulfilled, onRejected),
    };
    for (const method of ["from", "where"]) {
      q[method] = () => q;
    }
    return q as never;
  }

  it("clamps oversized titles to the column limit instead of poisoning the chunk", async () => {
    process.env.ALLOW_PRIVATE_FEED_URLS = "true";
    try {
      const { db, inserted } = importDb();
      vi.mocked(getDb).mockResolvedValue(db as never);

      const longTitle = "x".repeat(600);
      const opml = `<?xml version="1.0"?><opml version="2.0"><body><outline type="rss" text="${longTitle}" xmlUrl="https://big.example/feed" /></body></opml>`;

      const outcome = await feedDiscoveryService.importOPML("u1", opml);

      expect(outcome.imported).toBe(1);
      expect((inserted[0] as { title: string }).title).toHaveLength(500);
    } finally {
      delete process.env.ALLOW_PRIVATE_FEED_URLS;
    }
  });
});
