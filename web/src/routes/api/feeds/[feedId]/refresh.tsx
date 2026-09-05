import { eq, and } from "drizzle-orm";
import { feeds } from "../../../../data/db/schema.js";
import { getDb } from "../../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../../lib/api/errors.js";
import { requireAuth } from "../../../../lib/api/auth.js";
import { getDataRuntime } from "../../../../data/runtime.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

export async function action({ params, context }: { params: Record<string, string>; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };
    const { feedId } = params;
    const db = await getDb();

    const [feed] = await db
      .select()
      .from(feeds)
      .where(and(
        eq(feeds.id, feedId),
        eq(feeds.userId, auth.id),
      ))
      .limit(1);

    if (!feed) {
      throw new AppError("Feed not found", 404);
    }

    const runtime = await getDataRuntime();
    await runtime.queue.add("feed.update-single", {
      feedId,
    });

    return jsonResponse({ message: "Feed refresh queued" });
  });
}
