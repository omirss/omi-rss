import { describe, it, expect } from "vitest";
import {
  estimateReadMinutes,
  formatAbsoluteDate,
  formatRelativeTime,
  htmlToPlainText,
  normalizeFeedUrl,
} from "./format.js";

describe("formatRelativeTime", () => {
  it("handles missing and invalid dates", () => {
    expect(formatRelativeTime(null)).toBe("Unknown date");
    expect(formatRelativeTime(undefined)).toBe("Unknown date");
    expect(formatRelativeTime("not-a-date")).toBe("Unknown date");
  });

  it("formats recent times", () => {
    expect(formatRelativeTime(new Date(Date.now() - 20 * 1000).toISOString())).toBe("Just now");
    expect(formatRelativeTime(new Date(Date.now() - 5 * 60 * 1000).toISOString())).toBe("5m ago");
    expect(formatRelativeTime(new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString())).toBe("3h ago");
    expect(formatRelativeTime(new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString())).toBe("2d ago");
  });

  it("falls back to an absolute date beyond a week", () => {
    const old = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const result = formatRelativeTime(old);
    expect(result).not.toBe("Unknown date");
    expect(result).not.toContain("ago");
    expect(result).toBe(formatAbsoluteDate(old));
  });
});

describe("htmlToPlainText", () => {
  it("strips tags and decodes entities", () => {
    expect(htmlToPlainText("<p>Hello <b>world</b>&nbsp;&amp; more</p>")).toBe("Hello world & more");
  });

  it("collapses whitespace and handles null", () => {
    expect(htmlToPlainText("  a\n\n  b  ")).toBe("a b");
    expect(htmlToPlainText(null)).toBe("");
    expect(htmlToPlainText(undefined)).toBe("");
  });
});

describe("estimateReadMinutes", () => {
  it("returns zero for empty content", () => {
    expect(estimateReadMinutes(null)).toBe(0);
    expect(estimateReadMinutes("")).toBe(0);
  });

  it("estimates from word count with a one-minute floor", () => {
    expect(estimateReadMinutes("one two three")).toBe(1);
    const words = Array.from({ length: 2200 }, (_, i) => `word${i}`).join(" ");
    expect(estimateReadMinutes(words)).toBe(10);
  });
});

describe("normalizeFeedUrl", () => {
  it("normalizes scheme, host case, www, and trailing slashes", () => {
    expect(normalizeFeedUrl("https://blog.rust-lang.org/feed.xml")).toBe("blog.rust-lang.org/feed.xml");
    expect(normalizeFeedUrl("http://Blog.Rust-Lang.org/feed.xml/")).toBe("blog.rust-lang.org/feed.xml");
    expect(normalizeFeedUrl("https://www.example.com/feed/")).toBe("example.com/feed");
    expect(normalizeFeedUrl("  https://example.com  ")).toBe("example.com");
  });

  it("keeps distinct paths distinct", () => {
    expect(normalizeFeedUrl("https://example.com/a.xml")).not.toBe(normalizeFeedUrl("https://example.com/b.xml"));
  });
});
