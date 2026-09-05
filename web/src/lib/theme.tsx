import { createContext } from "preact";
import { useContext, useEffect, useMemo, useState, type StateUpdater } from "preact/hooks";

export type ThemeMode = "system" | "light" | "dark";
export type ResolvedMode = "light" | "dark";

export interface ThemePresetInfo {
  id: string;
  name: string;
  swatchFrom: string;
  swatchTo: string;
}

export const THEME_PRESETS: ThemePresetInfo[] = [
  { id: "glass", name: "Glass", swatchFrom: "#5263d0", swatchTo: "#7d5fad" },
  { id: "glass_light", name: "Glass Light", swatchFrom: "#7b8ff0", swatchTo: "#9c7cbe" },
  { id: "aurora", name: "Aurora", swatchFrom: "#14b8a6", swatchTo: "#0ea5e9" },
  { id: "ember", name: "Ember", swatchFrom: "#f59e0b", swatchTo: "#ef6c00" },
  { id: "mono", name: "Mono", swatchFrom: "#94a3b8", swatchTo: "#64748b" },
];

export const DEFAULT_PRESET_ID = "glass";
export const DEFAULT_MODE: ThemeMode = "system";

const PRESET_STORAGE_KEY = "omi.theme.preset";
const MODE_STORAGE_KEY = "omi.theme.mode";
export const THEME_COOKIE_NAME = "omi_theme";

export function isPresetId(value: unknown): value is string {
  return typeof value === "string" && THEME_PRESETS.some((preset) => preset.id === value);
}

export function isThemeMode(value: unknown): value is ThemeMode {
  return value === "system" || value === "light" || value === "dark";
}

export function resolveMode(mode: ThemeMode, prefersLight: boolean): ResolvedMode {
  if (mode === "system") return prefersLight ? "light" : "dark";
  return mode;
}

export function encodeThemeCookie(preset: string, mode: ThemeMode): string {
  return `${preset}:${mode}`;
}

export function parseThemeCookie(raw: string | undefined | null): { preset: string | null; mode: ThemeMode | null } {
  if (!raw) return { preset: null, mode: null };
  const [preset, mode] = decodeURIComponent(raw).split(":");
  return {
    preset: isPresetId(preset) ? preset : null,
    mode: isThemeMode(mode) ? mode : null,
  };
}

export function readStoredTheme(): { preset: string; mode: ThemeMode } {
  let preset: string | null = null;
  let mode: ThemeMode | null = null;
  try {
    preset = localStorage.getItem(PRESET_STORAGE_KEY);
    mode = localStorage.getItem(MODE_STORAGE_KEY) as ThemeMode | null;
  } catch {
    return { preset: DEFAULT_PRESET_ID, mode: DEFAULT_MODE };
  }
  if (isPresetId(preset) && isThemeMode(mode)) {
    return { preset, mode };
  }
  const cookie = parseThemeCookie(getCookieValue(THEME_COOKIE_NAME));
  return {
    preset: cookie.preset ?? DEFAULT_PRESET_ID,
    mode: cookie.mode ?? DEFAULT_MODE,
  };
}

export function getCookieValue(name: string): string | undefined {
  const match = document.cookie.match(new RegExp(`(?:^|; )${name}=([^;]*)`));
  return match ? match[1] : undefined;
}

function persistTheme(preset: string, mode: ThemeMode): void {
  try {
    localStorage.setItem(PRESET_STORAGE_KEY, preset);
    localStorage.setItem(MODE_STORAGE_KEY, mode);
  } catch {
    return;
  }
  document.cookie = `${THEME_COOKIE_NAME}=${encodeURIComponent(encodeThemeCookie(preset, mode))}; Path=/; Max-Age=31536000; SameSite=Lax`;
}

export function applyThemeAttributes(preset: string, mode: ThemeMode, prefersLight: boolean): ResolvedMode {
  const resolved = resolveMode(mode, prefersLight);
  const root = document.documentElement;
  root.setAttribute("data-preset", preset);
  root.setAttribute("data-mode", resolved);
  return resolved;
}

interface ThemeContextValue {
  preset: string;
  mode: ThemeMode;
  resolvedMode: ResolvedMode;
  setPreset: (preset: string) => void;
  setMode: (mode: StateUpdater<ThemeMode> | ThemeMode) => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: preact.ComponentChildren }) {
  const [preset, setPresetState] = useState(DEFAULT_PRESET_ID);
  const [mode, setModeState] = useState<ThemeMode>(DEFAULT_MODE);
  const [resolvedMode, setResolvedMode] = useState<ResolvedMode>("dark");
  const [hydrated, setHydrated] = useState(false);

  useEffect(() => {
    const stored = readStoredTheme();
    setPresetState(stored.preset);
    setModeState(stored.mode);
    setHydrated(true);
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    const media = window.matchMedia("(prefers-color-scheme: light)");
    const update = () => {
      setResolvedMode(applyThemeAttributes(preset, mode, media.matches));
    };
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, [preset, mode, hydrated]);

  const value = useMemo<ThemeContextValue>(() => ({
    preset,
    mode,
    resolvedMode,
    setPreset: (next: string) => {
      if (!isPresetId(next)) return;
      setPresetState(next);
      persistTheme(next, mode);
    },
    setMode: (next) => {
      const resolved = typeof next === "function" ? next(mode) : next;
      setModeState(resolved);
      persistTheme(preset, resolved);
    },
  }), [preset, mode, resolvedMode]);

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const context = useContext(ThemeContext);
  if (!context) {
    throw new Error("useTheme must be used within ThemeProvider");
  }
  return context;
}
