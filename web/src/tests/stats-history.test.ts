import { describe, it, expect } from "vitest";
import { HISTORY_DATE_FORMATS } from "../routes/api/stats/history.js";

describe("stats/history date formats", () => {
  it("uses Postgres TO_CHAR patterns, not strftime", () => {
    expect(HISTORY_DATE_FORMATS.day).toBe("YYYY-MM-DD");
    expect(HISTORY_DATE_FORMATS.month).toBe("YYYY-MM");
    expect(HISTORY_DATE_FORMATS.year).toBe("YYYY");
    for (const format of Object.values(HISTORY_DATE_FORMATS)) {
      expect(format).not.toContain("%");
    }
  });

  it("labels months as YYYY-MM (e.g. 2026-09)", () => {
    expect(HISTORY_DATE_FORMATS.month).toBe("YYYY-MM");
    expect("YYYY-MM").not.toMatch(/%/);
  });
});
