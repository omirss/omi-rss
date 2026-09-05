import { handleLoader } from "../../../../lib/api/errors.js";
import { requireAuth } from "../../../../lib/api/auth.js";
import { feedDiscoveryService } from "../../../../services/discovery.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

export async function loader({ context }: { context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };

    const opmlContent = await feedDiscoveryService.exportOPML(auth.id);

    return new Response(opmlContent, {
      status: 200,
      headers: {
        "Content-Type": "application/xml",
        "Content-Disposition": 'attachment; filename="omi-rss-feeds.opml"',
      },
    });
  });
}
