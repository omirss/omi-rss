import { z } from "zod";
import { eq, and, sql, between } from "drizzle-orm";
import { userArticleStates } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { handleLoader, jsonResponse, errorResponse } from "../../../lib/api/errors.js";
import { requireAuth } from "../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const dateRangeSchema = z.object({
  startDate: z.string().datetime().optional(),
  endDate: z.string().datetime().optional(),
  period: z.enum(["day", "week", "month", "year"]).default("month"),
});

// Ported from Express routes/stats.routes.ts GET /history.
export async function loader({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };
    const query = Object.fromEntries(new URL(request.url).searchParams.entries());

    const parsed = dateRangeSchema.safeParse(query);
    if (!parsed.success) {
      return errorResponse(parsed.error);
    }
    const { startDate, endDate, period } = parsed.data;

    const db = await getDb();

    const start = startDate ? new Date(startDate) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const end = endDate ? new Date(endDate) : new Date();

    const dateFormat = {
      day: "%Y-%m-%d",
      week: "%Y-%W",
      month: "%Y-%m",
      year: "%Y",
    }[period];

    const readingData = await db
      .select({
        period: sql<string>`
          TO_CHAR(${userArticleStates.readAt}, '${sql.raw(dateFormat)}')
        `,
        count: sql<number>`COUNT(*)`,
      })
      .from(userArticleStates)
      .where(
        and(
          eq(userArticleStates.userId, auth.id),
          eq(userArticleStates.isRead, true),
          between(userArticleStates.readAt, start, end),
        ),
      )
      .groupBy(sql`TO_CHAR(${userArticleStates.readAt}, '${sql.raw(dateFormat)}')`)
      .orderBy(sql`TO_CHAR(${userArticleStates.readAt}, '${sql.raw(dateFormat)}')`);

    return jsonResponse({
      period,
      startDate: start.toISOString(),
      endDate: end.toISOString(),
      data: readingData,
    });
  });
}
