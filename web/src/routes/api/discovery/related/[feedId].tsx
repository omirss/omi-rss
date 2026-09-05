import { z } from "zod";
import { handleLoader, jsonResponse } from "../../../../lib/api/errors.js";
import { validationFailure } from "../../../../lib/api/validate.js";
import { requireAuth } from "../../../../lib/api/auth.js";
import { feedDiscoveryService } from "../../../../services/discovery.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const relatedSchema = z.object({
  limit: z.coerce.number().int().min(1).max(20).optional(),
});

export async function loader({ request, params, context }: { request: Request; params: Record<string, string>; context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const query = Object.fromEntries(new URL(request.url).searchParams.entries());

    const parsed = relatedSchema.safeParse(query);
    if (!parsed.success) {
      return validationFailure(parsed.error);
    }

    const { feedId } = params;
    const { limit } = parsed.data;

    const related = await feedDiscoveryService.getRelatedFeeds(
      feedId,
      limit,
    );

    return jsonResponse({
      success: true,
      data: related,
    });
  });
}
