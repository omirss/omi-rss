import { describe, it, expect } from "vitest";
import { isFeedDue, extractionBudgetExceeded, articleExtractionOutcome } from "./worker.js";

// Unit tests for the update-all due-feed filter, extracted from the Express
// SQL: active AND (never fetched OR fetched strictly longer than
// updateInterval minutes ago). NULL interval arithmetic never becomes due
// on its own, matching the SQL comparison.

const NOW = new Date("2026-01-01T12:00:00.000Z");

function minutesAgo(minutes: number): Date {
  return new Date(NOW.getTime() - minutes * 60 * 1000);
}

describe("isFeedDue", () => {
  it("should be due when never fetched", () => {
    expect(isFeedDue({ isActive: true, lastFetchedAt: null, updateInterval: 30 }, NOW)).toBe(true);
  });

  it("should be due when fetched with a null interval but never fetched wins", () => {
    expect(isFeedDue({ isActive: true, lastFetchedAt: null, updateInterval: null }, NOW)).toBe(true);
  });

  it("should not be due before the interval elapses", () => {
    expect(isFeedDue({ isActive: true, lastFetchedAt: minutesAgo(10), updateInterval: 30 }, NOW)).toBe(false);
  });

  it("should not be due exactly at the interval boundary", () => {
    expect(isFeedDue({ isActive: true, lastFetchedAt: minutesAgo(30), updateInterval: 30 }, NOW)).toBe(false);
  });

  it("should be due after the interval elapses", () => {
    expect(isFeedDue({ isActive: true, lastFetchedAt: minutesAgo(31), updateInterval: 30 }, NOW)).toBe(true);
  });

  it("should honor per-feed update intervals", () => {
    const fetched = minutesAgo(10);
    expect(isFeedDue({ isActive: true, lastFetchedAt: fetched, updateInterval: 5 }, NOW)).toBe(true);
    expect(isFeedDue({ isActive: true, lastFetchedAt: fetched, updateInterval: 60 }, NOW)).toBe(false);
  });

  it("should never be due when inactive", () => {
    expect(isFeedDue({ isActive: false, lastFetchedAt: null, updateInterval: 30 }, NOW)).toBe(false);
    expect(isFeedDue({ isActive: false, lastFetchedAt: minutesAgo(120), updateInterval: 30 }, NOW)).toBe(false);
  });

  it("should not be due with a fetched feed and a null interval (SQL NULL comparison)", () => {
    expect(isFeedDue({ isActive: true, lastFetchedAt: minutesAgo(120), updateInterval: null }, NOW)).toBe(false);
  });
});

describe("extractionBudgetExceeded", () => {
  const startedAt = 1000000;

  it("allows extraction while under both the article count and time budget", () => {
    expect(extractionBudgetExceeded(startedAt, 0, startedAt + 1000)).toBe(false);
    expect(extractionBudgetExceeded(startedAt, 19, startedAt + 9999)).toBe(false);
  });

  it("stops after 20 articles", () => {
    expect(extractionBudgetExceeded(startedAt, 20, startedAt + 1000)).toBe(true);
    expect(extractionBudgetExceeded(startedAt, 25, startedAt + 1000)).toBe(true);
  });

  it("stops after 10 seconds even with articles remaining", () => {
    expect(extractionBudgetExceeded(startedAt, 3, startedAt + 10000)).toBe(true);
    expect(extractionBudgetExceeded(startedAt, 3, startedAt + 15000)).toBe(true);
  });
});

describe("articleExtractionOutcome", () => {
  it("skips safely on unsafe article URLs without fetching (SSRF)", async () => {
    expect(await articleExtractionOutcome({ url: "file:///etc/passwd" }, null)).toBe("skip-unsafe-url");
    expect(await articleExtractionOutcome({ url: "http://127.0.0.1:6380/x" }, null)).toBe("skip-unsafe-url");
    expect(await articleExtractionOutcome({ url: "https://192.168.1.10/internal" }, null)).toBe("skip-unsafe-url");
  });

  it("fetches safe literal-IP URLs without DNS lookups", async () => {
    expect(await articleExtractionOutcome({ url: "https://8.8.8.8/post" }, null)).toBe("fetch");
  });

  it("is terminal once an article has been extracted (fetch once, never re-fetch)", async () => {
    expect(await articleExtractionOutcome({ url: "https://8.8.8.8/post" }, "")).toBe("already-extracted");
    expect(await articleExtractionOutcome({ url: "https://8.8.8.8/post" }, "<p>done</p>")).toBe("already-extracted");
  });

  it("handles missing articles and empty URLs", async () => {
    expect(await articleExtractionOutcome(undefined, null)).toBe("missing");
    expect(await articleExtractionOutcome({ url: "" }, null)).toBe("skip-no-url");
  });
});
