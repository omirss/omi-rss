import { z } from "zod";
import { eq, and, desc, asc, sql, or, ilike, type SQL } from "drizzle-orm";
import { articles, userArticleStates, feeds } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { handle, handleLoader, jsonResponse } from "../../../lib/api/errors.js";
import { requireAuth } from "../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const paginationSchema = z.object({
  page: z.string().default("1").transform(Number).pipe(z.number().int().min(1)),
  limit: z.string().default("20").transform(Number).pipe(z.number().int().min(1).max(200)),
  sortBy: z.enum(["publishedAt", "title", "feedTitle"]).default("publishedAt"),
  sortOrder: z.enum(["asc", "desc"]).default("desc"),
});

const filterSchema = z.object({
  feedId: z.string().uuid().optional(),
  folderId: z.string().uuid().optional(),
  isRead: z.string().transform(val => val === "true").optional(),
  isStarred: z.string().transform(val => val === "true").optional(),
  search: z.string().optional(),
});

export async function loader({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };
    const query = Object.fromEntries(new URL(request.url).searchParams.entries());
    const pagination = paginationSchema.parse(query);
    const filters = filterSchema.parse(query);
    const db = await getDb();

    const conditions: Array<SQL | undefined> = [eq(feeds.userId, auth.id)];

    if (filters.feedId) {
      conditions.push(eq(articles.feedId, filters.feedId));
    }

    if (filters.folderId) {
      conditions.push(eq(feeds.folderId, filters.folderId));
    }

    if (filters.isRead !== undefined) {
      if (filters.isRead) {
        conditions.push(eq(userArticleStates.isRead, true));
      } else {
        conditions.push(
          or(
            eq(userArticleStates.isRead, false),
            sql`${userArticleStates.isRead} IS NULL`,
          ),
        );
      }
    }

    if (filters.isStarred !== undefined) {
      // The LEFT JOIN yields NULL for articles with no state row — the
      // response renders those as unstarred, so isStarred=false must
      // include them (plain `= false` would reject NULL).
      conditions.push(
        sql`COALESCE(${userArticleStates.isStarred}, false) = ${filters.isStarred}`,
      );
    }

    if (filters.search) {
      conditions.push(
        or(
          ilike(articles.title, `%${filters.search}%`),
          ilike(articles.summary, `%${filters.search}%`),
          ilike(articles.content, `%${filters.search}%`),
        ),
      );
    }

    const sortColumn = {
      publishedAt: articles.publishedAt,
      title: articles.title,
      feedTitle: feeds.title,
    }[pagination.sortBy];

    const offset = (pagination.page - 1) * pagination.limit;

    const articleList = await db
      .select({
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
      })
      .from(articles)
      .innerJoin(feeds, eq(articles.feedId, feeds.id))
      .leftJoin(
        userArticleStates,
        and(
          eq(userArticleStates.articleId, articles.id),
          eq(userArticleStates.userId, auth.id),
        ),
      )
      .where(and(...conditions))
      // Unique tie-breaker in the same direction as the sort column, so
      // offset/limit page boundaries are deterministic across pages even
      // inside large same-timestamp groups.
      .orderBy(
        pagination.sortOrder === "desc" ? desc(sortColumn) : asc(sortColumn),
        pagination.sortOrder === "desc" ? desc(articles.id) : asc(articles.id),
      )
      .limit(pagination.limit)
      .offset(offset);

    const [{ count }] = await db
      .select({ count: sql<number>`COUNT(*)` })
      .from(articles)
      .innerJoin(feeds, eq(articles.feedId, feeds.id))
      .leftJoin(
        userArticleStates,
        and(
          eq(userArticleStates.articleId, articles.id),
          eq(userArticleStates.userId, auth.id),
        ),
      )
      .where(and(...conditions));

    return jsonResponse({
      articles: articleList.map(article => ({
        ...article,
        isRead: article.isRead || false,
        isStarred: article.isStarred || false,
      })),
      pagination: {
        page: pagination.page,
        limit: pagination.limit,
        total: Number(count),
        totalPages: Math.ceil(Number(count) / pagination.limit),
      },
    });
  });
}
