import { z } from "zod";
import { handle, jsonResponse, errorResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { analyticsService } from "../../../services/analytics.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const trackArticleReadSchema = z.object({
  articleId: z.string(),
  scrollDepth: z.number().min(0).max(100),
  interactionTime: z.number().positive(),
  completed: z.boolean(),
});

// Ported from server/src/routes/analytics.ts POST /article-read.
export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };

    const parsed = trackArticleReadSchema.safeParse(await readJsonBody(request));
    if (!parsed.success) {
      return errorResponse(parsed.error);
    }

    await analyticsService.trackArticleRead(auth.id, parsed.data);
    return jsonResponse({ success: true });
  });
}
