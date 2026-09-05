import type { ComponentChildren, VNode } from "preact";
import { AlertIcon } from "./Icons.js";

export function EmptyState({
  icon,
  title,
  description,
  action,
}: {
  icon?: VNode;
  title: string;
  description?: string;
  action?: ComponentChildren;
}) {
  return (
    <div class="empty-state">
      <div class="empty-state-icon">{icon}</div>
      <div class="empty-state-title">{title}</div>
      {description ? <p class="empty-state-description">{description}</p> : null}
      {action}
    </div>
  );
}

export function ErrorState({
  title = "Something went wrong",
  message,
  onRetry,
}: {
  title?: string;
  message?: string;
  onRetry?: () => void;
}) {
  return (
    <div class="error-state">
      <div class="error-state-icon">
        <AlertIcon size={24} />
      </div>
      <div class="error-state-title">{title}</div>
      {message ? <p class="error-state-message">{message}</p> : null}
      {onRetry ? (
        <button type="button" class="btn btn-secondary btn-sm" onClick={onRetry}>
          Try again
        </button>
      ) : null}
    </div>
  );
}

export function Skeleton({ variant = "text", width }: { variant?: "text" | "block" | "circle"; width?: string }) {
  const cls = variant === "text" ? "skeleton skeleton-text" : variant === "circle" ? "skeleton skeleton-circle" : "skeleton skeleton-block";
  return <div class={cls} style={width ? `width: ${width}` : undefined} />;
}

export function SkeletonList({ rows = 4 }: { rows?: number }) {
  return (
    <div style="display: flex; flex-direction: column; gap: var(--sp-lg);">
      {Array.from({ length: rows }, (_, index) => (
        <div key={index} class="glass-card" style="display: flex; gap: var(--sp-lg); padding: var(--sp-lg);">
          <Skeleton variant="circle" />
          <div style="flex: 1; display: flex; flex-direction: column; gap: var(--sp-sm);">
            <Skeleton width="70%" />
            <Skeleton width="45%" />
            <Skeleton width="90%" />
          </div>
        </div>
      ))}
    </div>
  );
}
