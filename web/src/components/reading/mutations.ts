import { useCallback } from "preact/hooks";
import type { ArticleListItem } from "../../lib/api-types.js";
import { articlesApi } from "../../lib/client.js";
import { useToast } from "../Toast.js";

export type ArticleStatePatch = Partial<Pick<ArticleListItem, "isRead" | "isStarred">>;

export function useArticleMutations(
  setArticles: (updater: (current: ArticleListItem[]) => ArticleListItem[]) => void,
) {
  const { showToast } = useToast();

  const applyPatch = useCallback(
    (articleId: string, patch: ArticleStatePatch) => {
      setArticles((current) => current.map((article) => (article.id === articleId ? { ...article, ...patch } : article)));
    },
    [setArticles],
  );

  const mutateState = useCallback(
    async (article: ArticleListItem, patch: ArticleStatePatch): Promise<boolean> => {
      const previous = { isRead: article.isRead, isStarred: article.isStarred };
      applyPatch(article.id, patch);
      try {
        await articlesApi.updateState(article.id, patch);
        return true;
      } catch {
        applyPatch(article.id, previous);
        showToast({ title: "Could not update article", message: "The change was reverted. Try again.", kind: "error" });
        return false;
      }
    },
    [applyPatch, showToast],
  );

  const markRead = useCallback(
    (article: ArticleListItem): Promise<boolean> => {
      if (article.isRead) return Promise.resolve(true);
      return mutateState(article, { isRead: true });
    },
    [mutateState],
  );

  const toggleStar = useCallback(
    (article: ArticleListItem): Promise<boolean> => mutateState(article, { isStarred: !article.isStarred }),
    [mutateState],
  );

  return { applyPatch, markRead, toggleStar };
}
