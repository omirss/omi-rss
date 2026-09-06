import { describe, it, expect } from "vitest";
import { faviconUrlFor } from "./favicon.js";

describe("faviconUrlFor", () => {
  it("derives the favicon from the site origin (https)", () => {
    expect(faviconUrlFor("https://example.com/some/path?query=1")).toBe(
      "https://example.com/favicon.ico",
    );
  });

  it("derives the favicon from the site origin (http)", () => {
    expect(faviconUrlFor("http://blog.example.org/feed.xml")).toBe(
      "http://blog.example.org/favicon.ico",
    );
  });

  it("drops the port only when scheme-default", () => {
    expect(faviconUrlFor("https://example.com:443/path")).toBe("https://example.com/favicon.ico");
    expect(faviconUrlFor("https://example.com:8443/path")).toBe(
      "https://example.com:8443/favicon.ico",
    );
  });

  it("returns null for missing or junk input", () => {
    expect(faviconUrlFor(null)).toBeNull();
    expect(faviconUrlFor(undefined)).toBeNull();
    expect(faviconUrlFor("")).toBeNull();
    expect(faviconUrlFor("not a url")).toBeNull();
    expect(faviconUrlFor("example.com/feed")).toBeNull();
  });
});
