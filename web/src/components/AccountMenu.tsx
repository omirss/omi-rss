import { useEffect, useRef, useState } from "preact/hooks";
import { useNavigate } from "@neutron-build/core/client";
import { useSession } from "../lib/auth.js";
import { THEME_PRESETS, useTheme, type ThemeMode } from "../lib/theme.js";
import { CheckIcon, LogoutIcon, MonitorIcon, MoonIcon, SettingsIcon, SunIcon } from "./Icons.js";

export function AccountMenu() {
  const { user, logout } = useSession();
  const { preset, mode, setPreset, setMode } = useTheme();
  const navigate = useNavigate();
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

  const initials = (() => {
    if (!user) return "";
    const first = user.firstName?.[0] ?? user.username[0] ?? "";
    const last = user.lastName?.[0] ?? "";
    return (first + last).toUpperCase() || user.username.slice(0, 2).toUpperCase();
  })();

  const goSettings = () => {
    setOpen(false);
    navigate("/settings");
  };

  const handleLogout = async () => {
    setOpen(false);
    await logout();
    navigate("/login");
  };

  const modeOptions: Array<{ value: ThemeMode; label: string; icon: preact.VNode }> = [
    { value: "system", label: "System", icon: <MonitorIcon size={15} /> },
    { value: "light", label: "Light", icon: <SunIcon size={15} /> },
    { value: "dark", label: "Dark", icon: <MoonIcon size={15} /> },
  ];

  return (
    <div class="account-menu-anchor" ref={rootRef}>
      <button
        type="button"
        class="btn btn-ghost btn-icon account-btn"
        onClick={() => setOpen((current) => !current)}
        aria-label="Account menu"
        aria-expanded={open}
      >
        <span class="topbar-avatar">
          {user?.avatarUrl ? <img src={user.avatarUrl} alt="" /> : initials}
        </span>
      </button>
      {open ? (
        <div class="account-popover glass-panel" role="dialog" aria-label="Account menu">
          <div class="account-user">
            <span class="account-user-name">{user ? `${user.firstName ?? ""} ${user.lastName ?? ""}`.trim() || user.username : ""}</span>
            <span class="account-user-email">{user?.email}</span>
          </div>
          <button type="button" class="account-item" onClick={goSettings}>
            <SettingsIcon size={16} />
            <span>Settings</span>
          </button>
          <div class="account-theme">
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
          <button type="button" class="account-item" onClick={() => void handleLogout()}>
            <LogoutIcon size={16} />
            <span>Log out</span>
          </button>
        </div>
      ) : null}
    </div>
  );
}
