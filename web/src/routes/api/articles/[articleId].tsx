import { eq, and } from "drizzle-orm";
import { articles, userArticleStates, feeds } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, handleLoader, jsonResponse } from "../../../lib/api/errors.js";
import { requireAuth } from "../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const articleColumns = {
  id: articles.id,
  feedId: articles.feedId,
  title: articles.title,
  url: articles.url,
  summary: articles.summary,
  content: articles.content,
  author: articles.author,
  publishedAt: articles.publishedAt,
  imageUrl: articles.imageUrl,
  enclosures: articles.enclosures,
  isRead: userArticleStates.isRead,
  isStarred: userArticleStates.isStarred,
  readAt: userArticleStates.readAt,
  feedTitle: feeds.title,
  feedFavicon: feeds.favicon,
};

export async function loader({ params, context }: { params: Record<string, string>; context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };
    const { articleId } = params;
    const db = await getDb();

    const [article] = await db
      .select(articleColumns)
      .from(articles)
      .innerJoin(feeds, eq(articles.feedId, feeds.id))
      .leftJoin(
        userArticleStates,
        and(
          eq(userArticleStates.articleId, articles.id),
          eq(userArticleStates.userId, auth.id),
        ),
      )
      .where(
        and(
          eq(articles.id, articleId),
          eq(feeds.userId, auth.id),
        ),
      )
      .limit(1);

    if (!article) {
      throw new AppError("Article not found", 404);
    }

    return jsonResponse({
      article: {
        ...article,
        isRead: article.isRead || false,
        isStarred: article.isStarred || false,
      },
    });
  });
}
