import { describe, it, expect } from "vitest";
import { computeReadingStreaks } from "./analytics.js";

const day = (iso: string, hour = 12) => new Date(`${iso}T${String(hour).padStart(2, "0")}:00:00`);

describe("computeReadingStreaks", () => {
  it("returns zeros for no reading history", () => {
    expect(computeReadingStreaks([], day("2026-09-05"))).toEqual({ currentStreak: 0, longestStreak: 0 });
  });

  it("counts a consecutive run ending today", () => {
    const dates = ["2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05"].map(d => day(d));
    expect(computeReadingStreaks(dates, day("2026-09-05"))).toEqual({ currentStreak: 5, longestStreak: 5 });
  });

  it("keeps the streak alive when the last read was yesterday", () => {
    const dates = ["2026-09-03", "2026-09-04"].map(d => day(d));
    expect(computeReadingStreaks(dates, day("2026-09-05"))).toEqual({ currentStreak: 2, longestStreak: 2 });
  });

  it("kills the current streak when the last read was two days ago but keeps longest", () => {
    const dates = ["2026-08-30", "2026-08-31", "2026-09-01", "2026-09-03"].map(d => day(d));
    expect(computeReadingStreaks(dates, day("2026-09-05"))).toEqual({ currentStreak: 0, longestStreak: 3 });
  });

  it("finds the longest run across a gap", () => {
    const dates = [
      "2026-08-01", "2026-08-02",
      "2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13",
      "2026-09-04", "2026-09-05",
    ].map(d => day(d));
    expect(computeReadingStreaks(dates, day("2026-09-05"))).toEqual({ currentStreak: 2, longestStreak: 4 });
  });

  it("deduplicates same-day reads", () => {
    const dates = [
      day("2026-09-04", 8),
      day("2026-09-04", 22),
      day("2026-09-05", 9),
    ];
    expect(computeReadingStreaks(dates, day("2026-09-05"))).toEqual({ currentStreak: 2, longestStreak: 2 });
  });

  it("treats reads across a DST spring-forward night as consecutive (23h day)", () => {
    // US DST spring-forward: 2026-03-08 (2am skipped) — 2026-03-07 to
    // 2026-03-08 is 23h apart, which ms-math breaks on.
    const dates = ["2026-03-05", "2026-03-06", "2026-03-07", "2026-03-08"].map(d => day(d));
    expect(computeReadingStreaks(dates, day("2026-03-08"))).toEqual({ currentStreak: 4, longestStreak: 4 });
  });

  it("treats reads across a DST fall-back night as consecutive (25h day)", () => {
    // US DST fall-back: 2026-11-01 (2am repeated) — 2026-10-31 to
    // 2026-11-01 is 25h apart.
    const dates = ["2026-10-31", "2026-11-01", "2026-11-02"].map(d => day(d));
    expect(computeReadingStreaks(dates, day("2026-11-02"))).toEqual({ currentStreak: 3, longestStreak: 3 });
  });

  it("handles a streak spanning a DST transition with an earlier gap", () => {
    const dates = ["2026-03-01", "2026-03-07", "2026-03-08", "2026-03-09"].map(d => day(d));
    expect(computeReadingStreaks(dates, day("2026-03-09"))).toEqual({ currentStreak: 3, longestStreak: 3 });
  });

  it("does not propagate the current streak past a gap (old i===1 bug)", () => {
    // Old overview code only assigned currentStreak at i===1, losing longer
    // streaks; ensure a 4-day live streak reports 4, not 1.
    const dates = ["2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05"].map(d => day(d));
    expect(computeReadingStreaks(dates, day("2026-09-05")).currentStreak).toBe(4);
  });
});
