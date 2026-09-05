import { z } from "zod";
import { handle, jsonResponse, errorResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { analyticsService } from "../../../services/analytics.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const trackFeedInteractionSchema = z.object({
  feedId: z.string(),
  action: z.enum(["subscribe", "unsubscribe", "mute", "favorite"]),
});

// Ported from server/src/routes/analytics.ts POST /feed-interaction.
export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };

    const parsed = trackFeedInteractionSchema.safeParse(await readJsonBody(request));
    if (!parsed.success) {
      return errorResponse(parsed.error);
    }

    await analyticsService.trackFeedInteraction(auth.id, parsed.data);
    return jsonResponse({ success: true });
  });
}
