import { z } from "zod";
import { handleLoader, jsonResponse, errorResponse } from "../../../lib/api/errors.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { analyticsService, type AnalyticsTimeframe } from "../../../services/analytics.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const getUserAnalyticsSchema = z.object({
  timeframe: z.enum(["day", "week", "month", "year", "all"]).default("month"),
});

// Ported from server/src/routes/analytics.ts GET /. Returns the real payload
// shape {reading, preferences, patterns, engagement, insights} derived from
// actual reading data — no fabricated metrics.
export async function loader({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };
    const query = Object.fromEntries(new URL(request.url).searchParams.entries());

    const parsed = getUserAnalyticsSchema.safeParse(query);
    if (!parsed.success) {
      return errorResponse(parsed.error);
    }

    const analytics = await analyticsService.getUserAnalytics(auth.id, parsed.data.timeframe as AnalyticsTimeframe);
    return jsonResponse(analytics);
  });
}
