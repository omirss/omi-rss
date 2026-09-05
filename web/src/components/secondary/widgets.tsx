import type { ComponentChildren } from "preact";
import { useEffect } from "preact/hooks";
import "./secondary.css";

export function formatMinutes(minutes: number): string {
  const value = Math.max(0, Math.round(minutes));
  if (value < 60) return `${value}m`;
  const hours = Math.floor(value / 60);
  const rest = value % 60;
  return rest === 0 ? `${hours}h` : `${hours}h ${rest}m`;
}

export function formatHour(hour: number): string {
  const h = ((hour % 24) + 24) % 24;
  const suffix = h < 12 ? "AM" : "PM";
  const display = h % 12 === 0 ? 12 : h % 12;
  return `${display} ${suffix}`;
}

export function formatDayShort(day: string): string {
  return day.slice(0, 3);
}

export function Section({ title, children }: { title?: string; children: ComponentChildren }) {
  return (
    <section class="sec-section animate-in">
      {title ? <div class="sec-title">{title}</div> : null}
      {children}
    </section>
  );
}

export function StatCard({
  value,
  label,
  hint,
}: {
  value: string;
  label: string;
  hint?: string;
}) {
  return (
    <div class="stat-card">
      <span class="stat-value">{value}</span>
      <span class="stat-label">{label}</span>
      {hint ? <span class="stat-hint">{hint}</span> : null}
    </div>
  );
}

export function StatGrid({ children }: { children: ComponentChildren }) {
  return <div class="stat-grid">{children}</div>;
}

export interface HBarItem {
  name: string;
  count: number;
  detail?: string;
}

export function HBarList({ items, emptyMessage = "Nothing to show yet" }: { items: HBarItem[]; emptyMessage?: string }) {
  if (items.length === 0) {
    return <p class="stat-hint">{emptyMessage}</p>;
  }
  const max = Math.max(...items.map((item) => item.count), 1);
  return (
    <div class="hbar-list">
      {items.map((item) => (
        <div class="hbar-row" key={item.name}>
          <div class="hbar-meta">
            <span class="hbar-name" title={item.name}>{item.name}</span>
            <span class="hbar-count">{item.detail ?? `${item.count}`}</span>
          </div>
          <div class="hbar-track">
            <div class="hbar-fill" style={`width: ${Math.max(2, Math.round((item.count / max) * 100))}%`} />
          </div>
        </div>
      ))}
    </div>
  );
}

export interface VBarItem {
  label: string;
  count: number;
}

export function VBarChart({ items, axisLabels }: { items: VBarItem[]; axisLabels?: [string, string] }) {
  if (items.length === 0) {
    return <p class="stat-hint">Nothing to show yet</p>;
  }
  const max = Math.max(...items.map((item) => item.count), 1);
  return (
    <div>
      <div class="vchart" role="img">
        {items.map((item, index) => (
          <div
            class="vchart-col"
            key={`${item.label}-${index}`}
            title={item.count > 0 ? `${item.label}: ${item.count}` : item.label}
          >
            {item.count > 0 ? (
              <div class="vchart-bar" style={`height: ${Math.max(4, Math.round((item.count / max) * 100))}%`} />
            ) : (
              <div class="vchart-bar-empty" />
            )}
          </div>
        ))}
      </div>
      {axisLabels ? (
        <div class="vchart-axis">
          <span>{axisLabels[0]}</span>
          <span>{axisLabels[1]}</span>
        </div>
      ) : null}
    </div>
  );
}

export function Meter({ percent }: { percent: number }) {
  const clamped = Math.max(0, Math.min(100, Math.round(percent)));
  return (
    <div class="meter" role="presentation">
      <div class="meter-fill" style={`width: ${clamped}%`} />
    </div>
  );
}

export function Modal({
  title,
  children,
  onClose,
}: {
  title: string;
  children: ComponentChildren;
  onClose: () => void;
}) {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [onClose]);

  return (
    <div
      class="modal-backdrop"
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div class="modal glass-panel" role="dialog" aria-modal="true" aria-label={title}>
        <h2 class="modal-title">{title}</h2>
        {children}
      </div>
    </div>
  );
}
