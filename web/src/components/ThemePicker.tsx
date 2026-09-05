import { useEffect, useRef, useState } from "preact/hooks";
import { CheckIcon, MonitorIcon, MoonIcon, SunIcon } from "./Icons.js";
import { THEME_PRESETS, useTheme, type ThemeMode } from "../lib/theme.js";

export function ThemePicker() {
  const { preset, mode, setPreset, setMode } = useTheme();
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: PointerEvent) => {
      if (rootRef.current && !rootRef.current.contains(event.target as Node)) {
        setOpen(false);
      }
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setOpen(false);
      }
    };
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  const modeOptions: Array<{ value: ThemeMode; label: string; icon: preact.VNode }> = [
    { value: "system", label: "System", icon: <MonitorIcon size={15} /> },
    { value: "light", label: "Light", icon: <SunIcon size={15} /> },
    { value: "dark", label: "Dark", icon: <MoonIcon size={15} /> },
  ];

  return (
    <div class="theme-popover-anchor" ref={rootRef}>
      <button
        type="button"
        class="btn btn-secondary btn-icon"
        onClick={() => setOpen((current) => !current)}
        aria-label="Change theme"
        aria-expanded={open}
      >
        {mode === "system" ? <MonitorIcon size={17} /> : mode === "light" ? <SunIcon size={17} /> : <MoonIcon size={17} />}
      </button>
      {open ? (
        <div class="theme-popover glass-panel" role="dialog" aria-label="Theme settings">
          <div class="theme-popover-title">Theme</div>
          <div class="theme-preset-list">
            {THEME_PRESETS.map((option) => (
              <button
                key={option.id}
                type="button"
                class={`theme-preset${preset === option.id ? " theme-preset-active" : ""}`}
                onClick={() => setPreset(option.id)}
              >
                <span
                  class="theme-preset-swatch"
                  style={`background: linear-gradient(135deg, ${option.swatchFrom}, ${option.swatchTo});`}
                />
                <span>{option.name}</span>
                {preset === option.id ? <CheckIcon size={15} class="theme-preset-check" /> : null}
              </button>
            ))}
          </div>
          <div class="theme-mode-row">
            <span class="theme-mode-label">Appearance</span>
            <div class="segmented">
              {modeOptions.map((option) => (
                <button
                  key={option.value}
                  type="button"
                  class={`segmented-item${mode === option.value ? " segmented-item-active" : ""}`}
                  onClick={() => setMode(option.value)}
                >
                  {option.icon}
                  {option.label}
                </button>
              ))}
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
