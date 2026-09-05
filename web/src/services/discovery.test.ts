import { describe, it, expect } from "vitest";
import { categoryMatchesFilter, DISCOVERY_CATEGORIES } from "./discovery.js";

describe("categoryMatchesFilter", () => {
  it("matches the category id (ids are authoritative)", () => {
    expect(categoryMatchesFilter(["technology"], { id: "technology", name: "Technology" })).toBe(true);
    expect(categoryMatchesFilter(["technology"], { id: "science", name: "Science" })).toBe(false);
  });

  it("matches the display name for back-compat", () => {
    expect(categoryMatchesFilter(["Technology"], { id: "technology", name: "Technology" })).toBe(true);
    expect(categoryMatchesFilter(["Business & Finance"], { id: "business", name: "Business & Finance" })).toBe(true);
  });

  it("matches id when the name differs from the id", () => {
    expect(categoryMatchesFilter(["business"], { id: "business", name: "Business & Finance" })).toBe(true);
    expect(categoryMatchesFilter(["ai"], { id: "ai", name: "AI & Machine Learning" })).toBe(true);
    expect(categoryMatchesFilter(["news"], { id: "news", name: "World News" })).toBe(true);
  });

  it("is case-insensitive and trims", () => {
    expect(categoryMatchesFilter([" TECHNOLOGY "], { id: "technology", name: "Technology" })).toBe(true);
  });

  it("matches when any of several filters applies", () => {
    expect(
      categoryMatchesFilter(["science", "programming"], { id: "programming", name: "Programming & Development" }),
    ).toBe(true);
  });
});

describe("DISCOVERY_CATEGORIES", () => {
  it("exposes one wire category per curated feed category with unique ids", () => {
    const categories = DISCOVERY_CATEGORIES();
    const ids = categories.map(c => c.id);

    expect(new Set(ids).size).toBe(categories.length);
    for (const category of categories) {
      expect(typeof category.id).toBe("string");
      expect(typeof category.name).toBe("string");
      expect(typeof category.description).toBe("string");
    }
  });

  it("includes the ids the discover UI chips send", () => {
    const ids = DISCOVERY_CATEGORIES().map(c => c.id);
    expect(ids).toContain("technology");
    expect(ids).toContain("business");
  });
});
