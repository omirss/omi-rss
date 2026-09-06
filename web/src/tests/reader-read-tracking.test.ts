import { describe, it, expect } from "vitest";
import { articleReadPayload } from "../components/reading/ReaderView.js";

// Reading-time payload contract: short articles that fit the reader
// viewport never fire scroll events (maxScroll stays 0), so a measured
// viewport fit counts as a full read (scrollDepth 100, completed true) —
// this is what closes the streaks/read-stats undercount where analytics
// said 0 but read-stats said 1.

describe("articleReadPayload", () => {
  it("treats a viewport-fitting article (no scroll possible) as fully read", () => {
    const startedAt = Date.now() - 30_000;
    const payload = articleReadPayload({ maxScroll: 0, contentFitsViewport: true, startedAt });

    expect(payload.scrollDepth).toBe(100);
    expect(payload.completed).toBe(true);
    expect(payload.interactionTime).toBe(30);
  });

  it("viewport fit wins even if a stray scroll percentage was recorded", () => {
    const payload = articleReadPayload({ maxScroll: 40, contentFitsViewport: true, startedAt: Date.now() });

    expect(payload.scrollDepth).toBe(100);
    expect(payload.completed).toBe(true);
  });

  it("overflowing articles report the max scroll percentage and complete at 90+", () => {
    const mid = articleReadPayload({ maxScroll: 50, contentFitsViewport: false, startedAt: Date.now() });
    expect(mid.scrollDepth).toBe(50);
    expect(mid.completed).toBe(false);

    const deep = articleReadPayload({ maxScroll: 95, contentFitsViewport: false, startedAt: Date.now() });
    expect(deep.scrollDepth).toBe(95);
    expect(deep.completed).toBe(true);
  });

  it("clamps interactionTime to a 1s floor and rounds", () => {
    const quick = articleReadPayload({ maxScroll: 0, contentFitsViewport: true, startedAt: Date.now() - 100 });
    expect(quick.interactionTime).toBe(1);

    const now = 1_000_000;
    const payload = articleReadPayload({ maxScroll: 10, contentFitsViewport: false, startedAt: now - 64_400 }, now);
    expect(payload.interactionTime).toBe(64);
  });
});
