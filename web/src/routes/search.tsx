import { useCallback, useEffect, useRef, useState } from "preact/hooks";
import type { JSX } from "preact";
import { AppShell } from "../components/AppShell.js";
import { EmptyState, ErrorState, SkeletonList } from "../components/states.js";
import { SearchIcon } from "../components/Icons.js";
import { useToast } from "../components/Toast.js";
import { articlesApi } from "../lib/client.js";
import type { ArticleListItem, Pagination } from "../lib/api-types.js";
import { ArticleList } from "../components/reading/ArticleList.js";
import { ReaderView } from "../components/reading/ReaderView.js";
import { useArticleMutations } from "../components/reading/mutations.js";
import "../components/reading/reading.css";

export const config = { mode: "app" };

const PAGE_SIZE = 25;
const RECENT_KEY = "omi.search.recent";
const RECENT_LIMIT = 8;
const DEBOUNCE_MS = 350;

type LoadStatus = "idle" | "loading" | "ready" | "error";
type LoadMode = "replace" | "append" | "silent";

function loadRecents(): string[] {
  try {
    const raw = localStorage.getItem(RECENT_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((item): item is string => typeof item === "string") : [];
  } catch {
    return [];
  }
}

export default function SearchPage() {
  const { showToast } = useToast();
  const [query, setQuery] = useState("");
  const [submitted, setSubmitted] = useState("");
  const [articles, setArticles] = useState<ArticleListItem[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [status, setStatus] = useState<LoadStatus>("idle");
  const [errorMessage, setErrorMessage] = useState("");
  const [loadingMore, setLoadingMore] = useState(false);
  const [page, setPage] = useState(1);
  const [readerIndex, setReaderIndex] = useState<number | null>(null);
  const [recents, setRecents] = useState<string[]>([]);

  const { markRead, toggleStar } = useArticleMutations(setArticles);

  const requestTokenRef = useRef(0);

  useEffect(() => {
    setRecents(loadRecents());
  }, []);

  useEffect(() => {
    const trimmed = query.trim();
    if (trimmed.length < 2) return;
    const timer = setTimeout(() => setSubmitted(trimmed), DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [query]);

  const addRecent = useCallback((term: string) => {
    setRecents((current) => {
      const next = [term, ...current.filter((item) => item !== term)].slice(0, RECENT_LIMIT);
      try {
        localStorage.setItem(RECENT_KEY, JSON.stringify(next));
      } catch {
        return current;
      }
      return next;
    });
  }, []);

  const runSearch = useCallback(
    async (term: string, nextPage: number, mode: LoadMode) => {
      const token = ++requestTokenRef.current;
      if (mode === "replace") setStatus("loading");
      if (mode === "append") setLoadingMore(true);
      try {
        const response = await articlesApi.list({ search: term, page: nextPage, limit: PAGE_SIZE, sortBy: "publishedAt", sortOrder: "desc" });
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
          showToast({ title: "Could not load more results", kind: "error" });
        } else {
          setStatus("error");
          setErrorMessage(error instanceof Error ? error.message : "Search failed");
        }
      } finally {
        if (token === requestTokenRef.current) setLoadingMore(false);
      }
    },
    [showToast],
  );

  useEffect(() => {
    const trimmed = submitted.trim();
    if (!trimmed) return;
    setPage(1);
    void runSearch(trimmed, 1, "replace");
    addRecent(trimmed);
  }, [submitted, runSearch, addRecent]);

  const onSubmit = (event: JSX.TargetedEvent<HTMLFormElement, Event>) => {
    event.preventDefault();
    const trimmed = query.trim();
    if (trimmed.length >= 2) setSubmitted(trimmed);
  };

  const loadMore = () => {
    if (loadingMore || !pagination || page >= pagination.totalPages) return;
    const next = page + 1;
    setPage(next);
    void runSearch(submitted, next, "append");
  };

  const total = pagination ? pagination.total : 0;
  const hasMore = pagination ? page < pagination.totalPages : false;

  let content;
  if (status === "idle") {
    content = (
      <EmptyState
        icon={<SearchIcon size={24} />}
        title="Search your library"
        description="Find articles by title, summary, or content across every feed you follow."
      />
    );
  } else if (status === "loading" && articles.length === 0) {
    content = <SkeletonList rows={5} />;
  } else if (status === "error") {
    content = <ErrorState title="Search failed" message={errorMessage} onRetry={() => void runSearch(submitted, 1, "replace")} />;
  } else if (articles.length === 0) {
    content = (
      <EmptyState
        icon={<SearchIcon size={24} />}
        title={`No results for "${submitted}"`}
        description="Try a different term or check the spelling."
      />
    );
  } else {
    content = (
      <ArticleList
        articles={articles}
        onOpen={setReaderIndex}
        onToggleStar={(article) => void toggleStar(article)}
        footer={
          <div class="article-list-footer">
            <span class="list-meta">
              {total} result{total === 1 ? "" : "s"} for "{submitted}"
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
    <AppShell title="Search">
      <div class="page">
        <form class="discover-add-form" onSubmit={onSubmit} role="search">
          <div class="input-wrap">
            <SearchIcon size={16} />
            <input
              class="input"
              type="search"
              value={query}
              onInput={(event) => setQuery(event.currentTarget.value)}
              placeholder="Search articles..."
              aria-label="Search articles"
              autocomplete="off"
            />
          </div>
          <button type="submit" class="btn btn-primary btn-sm" disabled={query.trim().length < 2}>
            Search
          </button>
        </form>
        {status === "idle" && recents.length > 0 ? (
          <div class="search-recents">
            <span class="search-recents-label">Recent:</span>
            {recents.map((term) => (
              <button
                key={term}
                type="button"
                class="chip"
                onClick={() => {
                  setQuery(term);
                  setSubmitted(term);
                }}
              >
                {term}
              </button>
            ))}
          </div>
        ) : null}
        {content}
      </div>
      {readerIndex !== null && articles[readerIndex] ? (
        <ReaderView
          articles={articles}
          index={readerIndex}
          onIndexChange={setReaderIndex}
          onClose={() => setReaderIndex(null)}
          onMarkRead={(article) => void markRead(article)}
          onToggleStar={(article) => toggleStar(article)}
        />
      ) : null}
    </AppShell>
  );
}
