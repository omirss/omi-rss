import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));

import { feedDiscoveryService } from "./discovery.js";
import { getDb } from "../lib/api/db.js";

// OPML export contract: page feeds do not round-trip as RSS xmlUrl
// outlines (audit-proven broken import), so export skips them entirely.

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
};

const PAGE_FEED = {
  id: "f2",
  userId: "u1",
  folderId: "folder-1",
  url: "https://page.example.com/blog",
  title: "Page Feed",
  siteUrl: "https://page.example.com",
  sourceType: "page",
};

const FOLDERS = [{ id: "folder-1", name: "Scraped" }];

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

  it("drops folders that would be empty after excluding page feeds", async () => {
    vi.mocked(getDb).mockResolvedValue(makeDb([[RSS_FEED, PAGE_FEED], FOLDERS]));

    const opml = await feedDiscoveryService.exportOPML("u1");

    expect(opml).not.toContain("Scraped");
    expect(opml).toContain("Uncategorized");
  });
});
