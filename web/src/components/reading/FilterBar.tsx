import type { ComponentChildren } from "preact";
import type { FeedWithUnread } from "../../lib/api-types.js";
import { toCount } from "../../lib/client.js";
import "./reading.css";

export type ArticleFilter = "all" | "unread" | "starred";

export interface FilterBarProps {
  filter: ArticleFilter;
  onFilterChange: (filter: ArticleFilter) => void;
  feeds: FeedWithUnread[] | null;
  feedId: string;
  onFeedChange: (feedId: string) => void;
  countLabel?: string;
  children?: ComponentChildren;
}

const FILTERS: Array<{ id: ArticleFilter; label: string }> = [
  { id: "all", label: "All" },
  { id: "unread", label: "Unread" },
  { id: "starred", label: "Starred" },
];

export function FilterBar({ filter, onFilterChange, feeds, feedId, onFeedChange, countLabel, children }: FilterBarProps) {
  return (
    <div class="filter-bar glass-card">
      <div class="segmented" role="tablist" aria-label="Article filter">
        {FILTERS.map((item) => (
          <button
            key={item.id}
            type="button"
            role="tab"
            aria-selected={filter === item.id}
            class={`segmented-item${filter === item.id ? " segmented-item-active" : ""}`}
            onClick={() => onFilterChange(item.id)}
          >
            {item.label}
          </button>
        ))}
      </div>
      {feeds && feeds.length > 0 ? (
        <select
          class="input feed-select"
          value={feedId}
          onChange={(event) => onFeedChange(event.currentTarget.value)}
          aria-label="Filter by feed"
        >
          <option value="">All feeds</option>
          {feeds.map((feed) => {
            const unread = toCount(feed.unreadCount);
            const label = feed.customTitle || feed.title;
            return (
              <option key={feed.id} value={feed.id}>
                {label}
                {unread > 0 ? ` (${unread})` : ""}
              </option>
            );
          })}
        </select>
      ) : null}
      {countLabel ? <span class="list-meta">{countLabel}</span> : null}
      <div class="filter-bar-actions">{children}</div>
    </div>
  );
}
