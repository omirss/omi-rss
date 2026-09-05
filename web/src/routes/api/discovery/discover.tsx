import { z } from "zod";
import { handleLoader, jsonResponse } from "../../../lib/api/errors.js";
import { validationFailure } from "../../../lib/api/validate.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { feedDiscoveryService } from "../../../services/discovery.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const discoverSchema = z.object({
  categories: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
});

export async function loader({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };
    const query = Object.fromEntries(new URL(request.url).searchParams.entries());

    const parsed = discoverSchema.safeParse(query);
    if (!parsed.success) {
      return validationFailure(parsed.error);
    }

    const { categories, limit } = parsed.data;

    const suggestions = await feedDiscoveryService.discoverFeeds(auth.id, {
      categories: categories ? categories.split(",") : undefined,
      limit,
    });

    return jsonResponse({
      success: true,
      data: suggestions,
    });
  });
}
