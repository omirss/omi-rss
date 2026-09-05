import { describe, it, expect } from "vitest";
import {
  THEME_PRESETS,
  encodeThemeCookie,
  parseThemeCookie,
  resolveMode,
  isPresetId,
  isThemeMode,
} from "./theme.js";

describe("theme presets", () => {
  it("exposes the five presets from the Flutter app", () => {
    expect(THEME_PRESETS.map((preset) => preset.id)).toEqual([
      "glass",
      "glass_light",
      "aurora",
      "ember",
      "mono",
    ]);
  });

  it("validates preset ids", () => {
    expect(isPresetId("aurora")).toBe(true);
    expect(isPresetId("neon")).toBe(false);
    expect(isPresetId(null)).toBe(false);
  });
});

describe("resolveMode", () => {
  it("resolves system from the media query", () => {
    expect(resolveMode("system", true)).toBe("light");
    expect(resolveMode("system", false)).toBe("dark");
  });

  it("passes explicit modes through", () => {
    expect(resolveMode("light", false)).toBe("light");
    expect(resolveMode("dark", true)).toBe("dark");
  });
});

describe("theme cookie", () => {
  it("round-trips preset and mode", () => {
    const raw = encodeThemeCookie("ember", "dark");
    expect(parseThemeCookie(encodeURIComponent(raw))).toEqual({ preset: "ember", mode: "dark" });
  });

  it("rejects unknown values", () => {
    expect(parseThemeCookie("neon:dark")).toEqual({ preset: null, mode: "dark" });
    expect(parseThemeCookie("aurora:solar")).toEqual({ preset: "aurora", mode: null });
    expect(parseThemeCookie(null)).toEqual({ preset: null, mode: null });
    expect(parseThemeCookie(undefined)).toEqual({ preset: null, mode: null });
  });

  it("validates modes", () => {
    expect(isThemeMode("system")).toBe(true);
    expect(isThemeMode("light")).toBe(true);
    expect(isThemeMode("dark")).toBe(true);
    expect(isThemeMode("solar")).toBe(false);
  });
});
