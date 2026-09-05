import { handleLoader } from "../../../lib/api/errors.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { analyticsService } from "../../../services/analytics.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

// Ported from server/src/routes/analytics.ts GET /export.
export async function loader({ context }: { context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };

    const exportData = await analyticsService.exportUserData(auth.id);

    return new Response(JSON.stringify(exportData), {
      status: 200,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Content-Disposition": `attachment; filename="omi-rss-analytics-${new Date().toISOString().split("T")[0]}.json"`,
      },
    });
  });
}
