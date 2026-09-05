import { useCallback, useEffect, useRef, useState } from "preact/hooks";
import { Link, route } from "@neutron-build/core/client";
import { AppShell } from "../components/AppShell.js";
import { EmptyState, ErrorState, SkeletonList } from "../components/states.js";
import { useToast } from "../components/Toast.js";
import { useSession } from "../lib/auth.js";
import { CheckIcon, CompassIcon, PlusIcon, RefreshIcon, RssIcon } from "../components/Icons.js";
import { articlesApi, feedsApi, toCount } from "../lib/client.js";
import type { ArticleListItem, ArticleQuery, FeedWithUnread, Pagination } from "../lib/api-types.js";
import { ArticleList } from "../components/reading/ArticleList.js";
import { FilterBar } from "../components/reading/FilterBar.js";
import type { ArticleFilter } from "../components/reading/FilterBar.js";
import { ReaderView } from "../components/reading/ReaderView.js";
import { useArticleMutations } from "../components/reading/mutations.js";
import { CheckDoubleIcon } from "../components/reading/icons.js";
import "../components/reading/reading.css";

export const config = { mode: "app" };

const PAGE_SIZE = 25;
const REFRESH_RELOAD_DELAYS = [8000, 20000];
const FOCUS_REFETCH_MS = 15000;

type LoadStatus = "loading" | "ready" | "error";
type LoadMode = "replace" | "append" | "silent";

export default function HomePage() {
  const { showToast } = useToast();
  const { status: sessionStatus } = useSession();
  const [filter, setFilter] = useState<ArticleFilter>("all");
  const [feedId, setFeedId] = useState("");
  const [page, setPage] = useState(1);
  const [articles, setArticles] = useState<ArticleListItem[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [feeds, setFeeds] = useState<FeedWithUnread[] | null>(null);
  const [status, setStatus] = useState<LoadStatus>("loading");
  const [errorMessage, setErrorMessage] = useState("");
  const [loadingMore, setLoadingMore] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [confirmingMarkAll, setConfirmingMarkAll] = useState(false);
  const [markingAll, setMarkingAll] = useState(false);
  const [readerIndex, setReaderIndex] = useState<number | null>(null);

  const { markRead, toggleStar } = useArticleMutations(setArticles);

  const requestTokenRef = useRef(0);
  const readWhileOpenRef = useRef(false);
  const lastFocusFetchRef = useRef(0);
  const reloadTimersRef = useRef<number[]>([]);
  const mountedRef = useRef(false);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      reloadTimersRef.current.forEach((timer) => clearTimeout(timer));
    };
  }, []);

  const buildQuery = useCallback(
    (nextPage: number): ArticleQuery => {
      const query: ArticleQuery = { page: nextPage, limit: PAGE_SIZE, sortBy: "publishedAt", sortOrder: "desc" };
      if (feedId) query.feedId = feedId;
      if (filter === "unread") query.isRead = false;
      if (filter === "starred") query.isStarred = true;
      return query;
    },
    [filter, feedId],
  );

  const load = useCallback(
    async (nextPage: number, mode: LoadMode) => {
      const token = ++requestTokenRef.current;
      if (mode === "replace") setStatus("loading");
      if (mode === "append") setLoadingMore(true);
      try {
        const response = await articlesApi.list(buildQuery(nextPage));
        if (token !== requestTokenRef.current) return;
        if (mode === "append") {
          setArticles((current) => {
            const seen = new Set(current.map((article) => article.id));
            return [...current, ...response.articles.filter((article) => !seen.has(article.id))];
          });
        } else {
          setArticles(response.articles);
        }
        setPagination(response.pagination);
        setStatus("ready");
        setErrorMessage("");
      } catch (error) {
        if (token !== requestTokenRef.current) return;
        if (mode === "append") {
          showToast({ title: "Could not load more articles", kind: "error" });
        } else {
          setStatus("error");
          setErrorMessage(error instanceof Error ? error.message : "Unable to load articles");
        }
      } finally {
        if (token === requestTokenRef.current) setLoadingMore(false);
      }
    },
    [buildQuery, showToast],
  );

  const fetchFeeds = useCallback(async () => {
    try {
      const response = await feedsApi.list();
      if (mountedRef.current) setFeeds(response.feeds);
    } catch {
      return;
    }
  }, []);

  useEffect(() => {
    if (sessionStatus !== "authenticated") return;
    void load(page, page === 1 ? "replace" : "append");
  }, [sessionStatus, filter, feedId, page, load]);

  useEffect(() => {
    if (sessionStatus !== "authenticated") return;
    void fetchFeeds();
  }, [sessionStatus, fetchFeeds]);

  useEffect(() => {
    const onFocus = () => {
      if (sessionStatus !== "authenticated" || readerIndex !== null || page !== 1) return;
      const now = Date.now();
      if (now - lastFocusFetchRef.current < FOCUS_REFETCH_MS) return;
      lastFocusFetchRef.current = now;
      void load(1, "silent");
      void fetchFeeds();
    };
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [sessionStatus, readerIndex, page, load, fetchFeeds]);

  const changeFilter = (next: ArticleFilter) => {
    if (next === filter && page === 1) return;
    setFilter(next);
    setPage(1);
  };

  const changeFeed = (next: string) => {
    if (next === feedId && page === 1) return;
    setFeedId(next);
    setPage(1);
  };

  const loadMore = () => {
    if (loadingMore || !pagination || page >= pagination.totalPages) return;
    setPage(page + 1);
  };

  const closeReader = () => {
    setReaderIndex(null);
    if (readWhileOpenRef.current) {
      readWhileOpenRef.current = false;
      if (filter === "unread") void load(1, "silent");
      void fetchFeeds();
    }
  };

  const handleReaderMarkRead = (article: ArticleListItem) => {
    readWhileOpenRef.current = true;
    void markRead(article);
  };

  const confirmMarkAll = async () => {
    setMarkingAll(true);
    try {
      const response = await articlesApi.markAllRead({ feedId: feedId || undefined });
      const count = toCount(response.count);
      showToast({
        title: count > 0 ? `Marked ${count} article${count === 1 ? "" : "s"} as read` : "No unread articles",
        kind: "success",
      });
      setConfirmingMarkAll(false);
      readWhileOpenRef.current = false;
      void load(1, "silent");
      void fetchFeeds();
    } catch (error) {
      showToast({
        title: "Could not mark articles as read",
        message: error instanceof Error ? error.message : undefined,
        kind: "error",
      });
    } finally {
      setMarkingAll(false);
    }
  };

  const refreshAll = async () => {
    if (!feeds || feeds.length === 0 || refreshing) return;
    setRefreshing(true);
    let queued = 0;
    for (const feed of feeds) {
      try {
        await feedsApi.refresh(feed.id);
        queued += 1;
      } catch {
        return;
      }
    }
    setRefreshing(false);
    if (queued > 0) {
      showToast({
        title: `Refreshing ${queued} feed${queued === 1 ? "" : "s"}`,
        message: "New articles will appear in a moment.",
        kind: "info",
      });
    } else {
      showToast({ title: "Could not queue refresh", kind: "error" });
    }
    for (const delay of REFRESH_RELOAD_DELAYS) {
      const timer = window.setTimeout(() => {
        if (!mountedRef.current) return;
        void load(1, "silent");
        void fetchFeeds();
      }, delay);
      reloadTimersRef.current.push(timer);
    }
  };

  const total = pagination ? toCount(pagination.total) : 0;
  const hasMore = pagination ? page < pagination.totalPages : false;

  let content;
  if (status === "loading" && articles.length === 0) {
    content = <SkeletonList rows={6} />;
  } else if (status === "error") {
    content = <ErrorState title="Failed to load articles" message={errorMessage} onRetry={() => void load(page, "replace")} />;
  } else if (feeds !== null && feeds.length === 0) {
    content = (
      <EmptyState
        icon={<RssIcon size={24} />}
        title="No feeds yet"
        description="Subscribe to your first feed and fresh articles will land here."
        action={
          <Link to={route("/discover")} class="btn btn-primary">
            <CompassIcon size={16} />
            Discover feeds
          </Link>
        }
      />
    );
  } else if (articles.length === 0) {
    if (filter === "unread") {
      content = (
        <EmptyState
          icon={<CheckIcon size={24} />}
          title="All caught up"
          description="No unread articles right now. Refresh your feeds or browse everything."
          action={
            <button type="button" class="btn btn-secondary" onClick={() => changeFilter("all")}>
              Browse all articles
            </button>
          }
        />
      );
    } else if (filter === "starred") {
      content = (
        <EmptyState
          icon={<RssIcon size={24} />}
          title="No starred articles"
          description="Star articles while reading to find them here later."
        />
      );
    } else {
      content = (
        <EmptyState
          icon={<RssIcon size={24} />}
          title={feedId ? "No articles from this feed yet" : "No articles yet"}
          description="Articles appear shortly after you subscribe. Try refreshing your feeds."
        />
      );
    }
  } else {
    content = (
      <ArticleList
        articles={articles}
        onOpen={setReaderIndex}
        onToggleStar={(article) => void toggleStar(article)}
        footer={
          <div class="article-list-footer">
            <span class="list-meta">
              Showing {articles.length} of {total}
            </span>
            {hasMore ? (
              <button type="button" class="btn btn-secondary btn-sm" onClick={loadMore} disabled={loadingMore}>
                {loadingMore ? <span class="spinner" /> : null}
                {loadingMore ? "Loading" : "Load more"}
              </button>
            ) : null}
          </div>
        }
      />
    );
  }

  return (
    <AppShell
      title="Home"
      actions={
        <Link to={route("/discover")} class="btn btn-secondary btn-sm">
          <PlusIcon size={15} />
          Add feed
        </Link>
      }
    >
      <div class="page">
        <FilterBar
          filter={filter}
          onFilterChange={changeFilter}
          feeds={feeds}
          feedId={feedId}
          onFeedChange={changeFeed}
          countLabel={status === "ready" && pagination ? `${total} article${total === 1 ? "" : "s"}` : undefined}
        >
          <button
            type="button"
            class="btn btn-secondary btn-sm"
            onClick={() => void refreshAll()}
            disabled={refreshing || !feeds || feeds.length === 0}
            title="Refresh all feeds"
          >
            {refreshing ? <span class="spinner" /> : <RefreshIcon size={15} />}
            {refreshing ? "Refreshing" : "Refresh"}
          </button>
          {filter !== "starred" ? (
            <button
              type="button"
              class="btn btn-secondary btn-sm"
              onClick={() => setConfirmingMarkAll(true)}
              disabled={status !== "ready" || articles.length === 0}
            >
              <CheckDoubleIcon size={15} />
              Mark all read
            </button>
          ) : null}
        </FilterBar>
        {content}
      </div>
      {readerIndex !== null && articles[readerIndex] ? (
        <ReaderView
          articles={articles}
          index={readerIndex}
          onIndexChange={setReaderIndex}
          onClose={closeReader}
          onMarkRead={handleReaderMarkRead}
          onToggleStar={(article) => toggleStar(article)}
        />
      ) : null}
      {confirmingMarkAll ? (
        <div
          class="modal-backdrop"
          onClick={(event) => {
            if (event.target === event.currentTarget) setConfirmingMarkAll(false);
          }}
        >
          <div class="modal glass-panel" role="dialog" aria-modal="true" aria-label="Mark all as read">
            <h3 class="modal-title">Mark all as read</h3>
            <p class="confirm-message">
              {feedId
                ? "Mark every article from this feed as read? This cannot be undone."
                : "Mark every article across all your feeds as read? This cannot be undone."}
            </p>
            <div class="modal-actions">
              <button type="button" class="btn btn-secondary btn-sm" onClick={() => setConfirmingMarkAll(false)} disabled={markingAll}>
                Cancel
              </button>
              <button type="button" class="btn btn-primary btn-sm" onClick={() => void confirmMarkAll()} disabled={markingAll}>
                {markingAll ? <span class="spinner" /> : <CheckIcon size={15} />}
                {markingAll ? "Marking" : "Mark all read"}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </AppShell>
  );
}
