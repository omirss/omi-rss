import { handleLoader, jsonResponse } from "../../../lib/api/errors.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { analyticsService } from "../../../services/analytics.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

// Ported from Express routes/analytics.ts GET /streaks.
export async function loader({ context }: { context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };

    const streaks = await analyticsService.getReadingStreaks(auth.id);
    return jsonResponse(streaks);
  });
}
