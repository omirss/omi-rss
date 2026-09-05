import { useCallback, useEffect, useRef, useState } from "preact/hooks";
import { AppShell } from "../components/AppShell.js";
import { EmptyState, ErrorState, SkeletonList } from "../components/states.js";
import { useToast } from "../components/Toast.js";
import { useSession } from "../lib/auth.js";
import { BookmarkIcon, RssIcon } from "../components/Icons.js";
import { articlesApi, toCount } from "../lib/client.js";
import type { ArticleListItem, Pagination } from "../lib/api-types.js";
import { ArticleList } from "../components/reading/ArticleList.js";
import { ReaderView } from "../components/reading/ReaderView.js";
import { useArticleMutations } from "../components/reading/mutations.js";
import "../components/reading/reading.css";

export const config = { mode: "app" };

const PAGE_SIZE = 25;

type LoadStatus = "loading" | "ready" | "error";
type LoadMode = "replace" | "append" | "silent";

export default function SavedPage() {
  const { showToast } = useToast();
  const { status: sessionStatus } = useSession();
  const [articles, setArticles] = useState<ArticleListItem[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [status, setStatus] = useState<LoadStatus>("loading");
  const [errorMessage, setErrorMessage] = useState("");
  const [loadingMore, setLoadingMore] = useState(false);
  const [page, setPage] = useState(1);
  const [readerIndex, setReaderIndex] = useState<number | null>(null);

  const { markRead, toggleStar } = useArticleMutations(setArticles);

  const requestTokenRef = useRef(0);

  const load = useCallback(
    async (nextPage: number, mode: LoadMode) => {
      const token = ++requestTokenRef.current;
      if (mode === "replace") setStatus("loading");
      if (mode === "append") setLoadingMore(true);
      try {
        const response = await articlesApi.list({ isStarred: true, page: nextPage, limit: PAGE_SIZE, sortBy: "publishedAt", sortOrder: "desc" });
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
          setErrorMessage(error instanceof Error ? error.message : "Unable to load saved articles");
        }
      } finally {
        if (token === requestTokenRef.current) setLoadingMore(false);
      }
    },
    [showToast],
  );

  useEffect(() => {
    if (sessionStatus !== "authenticated") return;
    void load(page, page === 1 ? "replace" : "append");
  }, [sessionStatus, page, load]);

  const removeArticle = (articleId: string) => {
    const removedIndex = articles.findIndex((article) => article.id === articleId);
    setArticles((current) => current.filter((article) => article.id !== articleId));
    setPagination((current) => (current ? { ...current, total: Math.max(0, toCount(current.total) - 1) } : current));
    if (readerIndex !== null && removedIndex !== -1) {
      if (removedIndex === readerIndex) {
        setReaderIndex(null);
      } else if (removedIndex < readerIndex) {
        setReaderIndex(readerIndex - 1);
      }
    }
  };

  const unstarFromList = async (article: ArticleListItem) => {
    const ok = await toggleStar(article);
    if (ok) {
      removeArticle(article.id);
      showToast({ title: "Removed from saved", kind: "success" });
    }
  };

  const handleReaderToggleStar = async (article: ArticleListItem): Promise<boolean> => {
    const ok = await toggleStar(article);
    if (ok) {
      showToast({ title: "Removed from saved", kind: "success" });
      removeArticle(article.id);
    }
    return ok;
  };

  const loadMore = () => {
    if (loadingMore || !pagination || page >= pagination.totalPages) return;
    setPage(page + 1);
  };

  const total = pagination ? toCount(pagination.total) : 0;
  const hasMore = pagination ? page < pagination.totalPages : false;

  let content;
  if (status === "loading" && articles.length === 0) {
    content = <SkeletonList rows={5} />;
  } else if (status === "error") {
    content = <ErrorState title="Failed to load saved articles" message={errorMessage} onRetry={() => void load(page, "replace")} />;
  } else if (articles.length === 0) {
    content = (
      <EmptyState
        icon={<BookmarkIcon size={24} />}
        title="No saved articles"
        description="Articles you star while reading are collected here for later."
      />
    );
  } else {
    content = (
      <ArticleList
        articles={articles}
        onOpen={setReaderIndex}
        onToggleStar={(article) => void unstarFromList(article)}
        footer={
          <div class="article-list-footer">
            <span class="list-meta">
              {total} saved article{total === 1 ? "" : "s"}
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
    <AppShell title="Saved">
      <div class="page">{content}</div>
      {readerIndex !== null && articles[readerIndex] ? (
        <ReaderView
          articles={articles}
          index={readerIndex}
          onIndexChange={setReaderIndex}
          onClose={() => setReaderIndex(null)}
          onMarkRead={(article) => void markRead(article)}
          onToggleStar={handleReaderToggleStar}
        />
      ) : null}
    </AppShell>
  );
}
