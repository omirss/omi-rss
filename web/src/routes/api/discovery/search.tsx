import { z } from "zod";
import { handleLoader, jsonResponse } from "../../../lib/api/errors.js";
import { validationFailure } from "../../../lib/api/validate.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { feedDiscoveryService } from "../../../services/discovery.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const searchSchema = z.object({
  q: z.string().min(2, "Query must be at least 2 characters"),
  category: z.string().optional(),
  language: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(50).optional(),
});

export async function loader({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };
    const query = Object.fromEntries(new URL(request.url).searchParams.entries());

    const parsed = searchSchema.safeParse(query);
    if (!parsed.success) {
      return validationFailure(parsed.error);
    }

    const { q, category, language, limit } = parsed.data;

    const results = await feedDiscoveryService.searchPublicFeeds(q, {
      category,
      language,
      limit,
    });

    return jsonResponse({
      success: true,
      data: results,
    });
  });
}
