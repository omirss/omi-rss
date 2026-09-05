import { useState } from "preact/hooks";
import type { JSX } from "preact";
import type { ArticleListItem } from "../../lib/api-types.js";
import { estimateReadMinutes, formatRelativeTime, htmlToPlainText } from "./format.js";
import { StarIcon } from "./icons.js";
import "./reading.css";

export interface ArticleRowProps {
  article: ArticleListItem;
  index: number;
  onOpen: (article: ArticleListItem, index: number) => void;
  onToggleStar?: (article: ArticleListItem) => void;
  showSnippet?: boolean;
}

function FeedAvatar({ src, name }: { src: string | null; name: string }) {
  const [failed, setFailed] = useState(false);
  const initial = (name || "?").trim().charAt(0).toUpperCase();
  if (!src || failed) {
    return <span class="article-avatar article-avatar-fallback">{initial}</span>;
  }
  return (
    <span class="article-avatar">
      <img src={src} alt="" loading="lazy" onError={() => setFailed(true)} />
    </span>
  );
}

export function ArticleRow({ article, index, onOpen, onToggleStar, showSnippet = true }: ArticleRowProps) {
  const snippet = article.summary || htmlToPlainText(article.content);
  const minutes = estimateReadMinutes(article.content || article.summary);

  const handleKeyDown = (event: JSX.TargetedKeyboardEvent<HTMLDivElement>) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onOpen(article, index);
    }
  };

  return (
    <div
      class={`article-row glass-card${article.isRead ? " is-read" : ""}`}
      role="button"
      tabIndex={0}
      onClick={() => onOpen(article, index)}
      onKeyDown={handleKeyDown}
      aria-label={article.title}
    >
      <FeedAvatar src={article.feedFavicon} name={article.feedTitle} />
      <div class="article-body">
        <span class="article-title">{article.title}</span>
        <span class="article-meta">
          <span class="article-meta-feed">{article.feedTitle}</span>
          <span class="article-meta-sep">·</span>
          <span>{formatRelativeTime(article.publishedAt)}</span>
          {minutes > 0 ? (
            <>
              <span class="article-meta-sep">·</span>
              <span>{minutes} min read</span>
            </>
          ) : null}
        </span>
        {showSnippet && snippet ? <span class="article-snippet">{snippet.slice(0, 220)}</span> : null}
      </div>
      <div class="article-side">
        <span class="article-dot" aria-hidden="true" />
        {onToggleStar ? (
          <button
            type="button"
            class={`btn btn-ghost btn-icon btn-sm article-star${article.isStarred ? " is-starred" : ""}`}
            onClick={(event) => {
              event.stopPropagation();
              onToggleStar(article);
            }}
            aria-label={article.isStarred ? "Unstar article" : "Star article"}
            aria-pressed={article.isStarred}
          >
            <StarIcon size={16} />
          </button>
        ) : null}
      </div>
    </div>
  );
}
