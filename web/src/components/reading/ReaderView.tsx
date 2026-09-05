import { useEffect, useMemo, useRef } from "preact/hooks";
import type { ArticleListItem } from "../../lib/api-types.js";
import { useToast } from "../Toast.js";
import { EmptyState } from "../states.js";
import { ChevronLeftIcon, CloseIcon, RssIcon } from "../Icons.js";
import { ChevronRightIcon, ExternalLinkIcon, StarIcon } from "./icons.js";
import { estimateReadMinutes, formatAbsoluteDate } from "./format.js";
import { sanitizeArticleHtml } from "./sanitize.js";
import "./reading.css";

export interface ReaderViewProps {
  articles: ArticleListItem[];
  index: number;
  onIndexChange: (index: number) => void;
  onClose: () => void;
  onMarkRead: (article: ArticleListItem) => void;
  onToggleStar: (article: ArticleListItem) => Promise<boolean> | boolean;
}

export function ReaderView({
  articles,
  index,
  onIndexChange,
  onClose,
  onMarkRead,
  onToggleStar,
}: ReaderViewProps) {
  const { showToast } = useToast();
  const article = articles[index];
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const articleId = article?.id ?? null;

  useEffect(() => {
    if (article && !article.isRead) {
      onMarkRead(article);
    }
  }, [articleId]);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = 0;
    }
  }, [articleId]);

  const bodyHtml = useMemo(() => {
    const raw = article?.content || article?.summary || "";
    return sanitizeArticleHtml(raw);
  }, [articleId]);

  const minutes = estimateReadMinutes(article?.content || article?.summary);

  const hasPrev = index > 0;
  const hasNext = index < articles.length - 1;

  const goNext = () => {
    if (hasNext) onIndexChange(index + 1);
  };

  const goPrev = () => {
    if (hasPrev) onIndexChange(index - 1);
  };

  const toggleStar = async () => {
    if (!article) return;
    const willStar = !article.isStarred;
    const ok = await onToggleStar(article);
    if (ok) {
      showToast({ title: willStar ? "Article starred" : "Article unstarred", kind: "success" });
    }
  };

  const openOriginal = () => {
    if (article) window.open(article.url, "_blank", "noopener,noreferrer");
  };

  const handleKeydown = (event: KeyboardEvent) => {
    if (event.defaultPrevented) return;
    const target = event.target as HTMLElement | null;
    if (
      target &&
      (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.tagName === "SELECT" || target.isContentEditable)
    ) {
      return;
    }
    if (event.key === "Escape") {
      event.preventDefault();
      onClose();
    } else if (event.key === "ArrowRight" || event.key === "j") {
      if (hasNext) {
        event.preventDefault();
        goNext();
      }
    } else if (event.key === "ArrowLeft" || event.key === "k") {
      if (hasPrev) {
        event.preventDefault();
        goPrev();
      }
    } else if (event.key === "s") {
      event.preventDefault();
      void toggleStar();
    } else if (event.key === "o") {
      event.preventDefault();
      openOriginal();
    }
  };

  useEffect(() => {
    window.addEventListener("keydown", handleKeydown);
    return () => window.removeEventListener("keydown", handleKeydown);
  });

  if (!article) return null;

  return (
    <div
      class="reader-backdrop"
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div class="reader-panel glass-panel" role="dialog" aria-modal="true" aria-label={article.title}>
        <header class="reader-header">
          <button type="button" class="btn btn-ghost btn-icon btn-sm" onClick={onClose} aria-label="Close reader">
            <CloseIcon size={17} />
          </button>
          <div class="reader-header-meta">
            <span class="reader-header-feed">{article.feedTitle}</span>
            <span class="reader-header-date">{formatAbsoluteDate(article.publishedAt)}</span>
          </div>
          <button
            type="button"
            class="btn btn-ghost btn-icon btn-sm"
            onClick={goPrev}
            disabled={!hasPrev}
            aria-label="Previous article"
            title="Previous article (k)"
          >
            <ChevronLeftIcon size={17} />
          </button>
          <button
            type="button"
            class={`btn btn-ghost btn-icon btn-sm article-star${article.isStarred ? " is-starred" : ""}`}
            onClick={() => void toggleStar()}
            aria-label={article.isStarred ? "Unstar article" : "Star article"}
            aria-pressed={article.isStarred}
            title="Toggle star (s)"
          >
            <StarIcon size={17} />
          </button>
          <a
            class="btn btn-ghost btn-icon btn-sm"
            href={article.url}
            target="_blank"
            rel="noopener noreferrer"
            aria-label="Open original article"
            title="Open original (o)"
          >
            <ExternalLinkIcon size={17} />
          </a>
          <button
            type="button"
            class="btn btn-ghost btn-icon btn-sm"
            onClick={goNext}
            disabled={!hasNext}
            aria-label="Next article"
            title="Next article (j)"
          >
            <ChevronRightIcon size={17} />
          </button>
        </header>
        <div class="reader-scroll" ref={scrollRef}>
          <h2 class="reader-title">{article.title}</h2>
          <div class="reader-meta">
            {article.author ? <span>{article.author}</span> : null}
            <span>{article.feedTitle}</span>
            <span>{formatAbsoluteDate(article.publishedAt)}</span>
            {minutes > 0 ? <span>{minutes} min read</span> : null}
          </div>
          {bodyHtml ? (
            <div class="reader-content" dangerouslySetInnerHTML={{ __html: bodyHtml }} />
          ) : (
            <div class="reader-empty">
              <EmptyState
                icon={<RssIcon size={24} />}
                title="No article content"
                description="This article has no extracted text to display."
                action={
                  <a class="btn btn-secondary btn-sm" href={article.url} target="_blank" rel="noopener noreferrer">
                    <ExternalLinkIcon size={15} />
                    Open original
                  </a>
                }
              />
            </div>
          )}
          <div class="reader-footer">
            <a class="reader-original-link" href={article.url} target="_blank" rel="noopener noreferrer">
              Open the original article
            </a>
            <span class="reader-shortcuts">
              <kbd class="reader-kbd">j</kbd>
              <kbd class="reader-kbd">k</kbd>
              navigate
              <kbd class="reader-kbd">s</kbd>
              star
              <kbd class="reader-kbd">esc</kbd>
              close
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
