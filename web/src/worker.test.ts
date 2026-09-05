import { describe, it, expect } from "vitest";
import { isFeedDue } from "./worker.js";

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
