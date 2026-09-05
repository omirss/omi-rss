import { z } from "zod";
import { AppError, handleLoader, jsonResponse } from "../../../../lib/api/errors.js";
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
    const auth = context.user as { id: string };
    const query = Object.fromEntries(new URL(request.url).searchParams.entries());

    const parsed = relatedSchema.safeParse(query);
    if (!parsed.success) {
      return validationFailure(parsed.error);
    }

    const { feedId } = params;
    const { limit } = parsed.data;

    const uuidParsed = z.string().uuid().safeParse(feedId);
    if (!uuidParsed.success) {
      throw new AppError("Feed not found", 404);
    }

    const related = await feedDiscoveryService.getRelatedFeeds(
      auth.id,
      feedId,
      limit,
    );

    return jsonResponse({
      success: true,
      data: related,
    });
  });
}
