import { useEffect, useMemo, useRef, useState } from "preact/hooks";
import type { ArticleDetail, ArticleListItem } from "../../lib/api-types.js";
import { analyticsApi, articlesApi } from "../../lib/client.js";
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

interface ActiveRead {
  articleId: string;
  startedAt: number;
  maxScroll: number;
  contentFitsViewport: boolean;
}

// Fire-and-forget analytics: at most one article-read post per article per
// page session, no matter how often it is opened or re-visited.
const trackedArticleIds = new Set<string>();

const SCROLL_COMPLETION_THRESHOLD = 90;
export const VIEWPORT_FIT_EPSILON_PX = 2;

export interface ArticleReadMetrics {
  maxScroll: number;
  contentFitsViewport: boolean;
  startedAt: number;
}

export interface ArticleReadPayload {
  scrollDepth: number;
  interactionTime: number;
  completed: boolean;
}

// Payload for trackArticleRead. Short articles that fit the reader
// viewport never fire scroll events (maxScroll stays 0), so a measured
// viewport fit counts as a full read: scrollDepth 100, completed true.
export function articleReadPayload(read: ArticleReadMetrics, now: number = Date.now()): ArticleReadPayload {
  const completed = read.contentFitsViewport || read.maxScroll >= SCROLL_COMPLETION_THRESHOLD;
  const scrollDepth = read.contentFitsViewport
    ? 100
    : Math.round(Math.min(100, Math.max(0, read.maxScroll)));
  return {
    scrollDepth,
    interactionTime: Math.max(1, Math.round((now - read.startedAt) / 1000)),
    completed,
  };
}

function flushReadTracking(active: ActiveRead | null): void {
  if (!active || trackedArticleIds.has(active.articleId)) return;
  trackedArticleIds.add(active.articleId);
  analyticsApi
    .trackArticleRead({ articleId: active.articleId, ...articleReadPayload(active) })
    .catch(() => undefined);
}

const FOCUSABLE_SELECTOR = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

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
  const panelRef = useRef<HTMLDivElement | null>(null);
  const articleId = article?.id ?? null;
  const activeReadRef = useRef<ActiveRead | null>(null);
  // contentExtracted lives in the detail payload, not the list — fetch it
  // on open and fall back to the list item's fields until it arrives.
  const [detail, setDetail] = useState<ArticleDetail | null>(null);

  useEffect(() => {
    let cancelled = false;
    setDetail(null);
    if (articleId) {
      articlesApi
        .get(articleId)
        .then((response) => {
          if (!cancelled) setDetail(response.article);
        })
        .catch(() => undefined);
    }
    return () => {
      cancelled = true;
    };
  }, [articleId]);

  // Reading-time tracking: start a clock per article, flush on navigate/close.
  useEffect(() => {
    const previous = activeReadRef.current;
    if (previous && previous.articleId !== articleId) {
      flushReadTracking(previous);
    }
    activeReadRef.current = articleId
      ? { articleId, startedAt: Date.now(), maxScroll: 0, contentFitsViewport: false }
      : null;
  }, [articleId]);

  // Final flush when the reader closes.
  useEffect(() => {
    return () => {
      flushReadTracking(activeReadRef.current);
      activeReadRef.current = null;
    };
  }, []);

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

  // Focus management: move focus into the dialog, trap Tab within it, and
  // restore focus to the invoking element on close.
  useEffect(() => {
    const previouslyFocused = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const firstButton = panelRef.current?.querySelector<HTMLElement>("button");
    (firstButton ?? panelRef.current)?.focus();
    return () => {
      previouslyFocused?.focus?.();
    };
  }, []);

  const handleScroll = () => {
    const el = scrollRef.current;
    const active = activeReadRef.current;
    if (!el || !active) return;
    const reachable = el.scrollHeight - el.clientHeight;
    const percent = reachable > 0 ? (el.scrollTop / reachable) * 100 : 100;
    if (percent > active.maxScroll) active.maxScroll = percent;
  };

  const bodyHtml = useMemo(() => {
    const raw = detail?.contentExtracted || article?.content || article?.summary || "";
    return sanitizeArticleHtml(raw);
  }, [articleId, detail]);

  // Viewport-fit snapshot for the active read: an article whose content
  // does not overflow the scroll container can never produce scroll
  // events, so completion is decided from this measurement at flush time.
  // Re-measured whenever the rendered content changes height (list
  // fallback -> fetched detail).
  useEffect(() => {
    const el = scrollRef.current;
    const active = activeReadRef.current;
    if (!el || !active || active.articleId !== articleId) return;
    active.contentFitsViewport = el.scrollHeight <= el.clientHeight + VIEWPORT_FIT_EPSILON_PX;
  }, [articleId, bodyHtml]);

  const minutes = estimateReadMinutes(detail?.contentExtracted || article?.content || article?.summary);

  // The body renders contentExtracted whenever it is non-empty (it leads the
  // fallback chain), so its presence means it was the source used.
  const usedFullText = Boolean(detail?.contentExtracted);

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

  const trapTab = (event: KeyboardEvent) => {
    const panel = panelRef.current;
    if (!panel) return;
    const focusables = Array.from(panel.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR))
      .filter((el) => el.offsetParent !== null || el === document.activeElement);
    if (focusables.length === 0) return;
    const first = focusables[0];
    const last = focusables[focusables.length - 1];
    const current = document.activeElement;
    if (event.shiftKey) {
      if (current === first || current === panel || !panel.contains(current)) {
        event.preventDefault();
        last.focus();
      }
    } else if (current === last || current === panel || !panel.contains(current)) {
      event.preventDefault();
      first.focus();
    }
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
    } else if (event.key === "Tab") {
      trapTab(event);
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
      <div class="reader-panel glass-panel" role="dialog" aria-modal="true" aria-label={article.title} ref={panelRef}>
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
        <div class="reader-scroll" ref={scrollRef} onScroll={handleScroll}>
          <h2 class="reader-title">{article.title}</h2>
          <div class="reader-meta">
            {article.author ? <span>{article.author}</span> : null}
            <span>{article.feedTitle}</span>
            <span>{formatAbsoluteDate(article.publishedAt)}</span>
            {minutes > 0 ? <span>{minutes} min read</span> : null}
            {usedFullText ? (
              <span class="reader-badge" role="img" aria-label="Rendered from extracted full text" title="Rendered from the extracted full article">
                Full text
              </span>
            ) : null}
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
            <span class="reader-footer-links">
              <a class="reader-original-link" href={article.url} target="_blank" rel="noopener noreferrer">
                Open the original article
              </a>
              {article.url ? (
                <>
                  <a class="reader-archive-link" href={`https://web.archive.org/web/${article.url}`} target="_blank" rel="noopener noreferrer">
                    archive.org
                  </a>
                  <a class="reader-archive-link" href={`https://archive.ph/newest/${article.url}`} target="_blank" rel="noopener noreferrer">
                    archive.today
                  </a>
                </>
              ) : null}
            </span>
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
