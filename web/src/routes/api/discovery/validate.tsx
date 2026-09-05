import { z } from "zod";
import { handle, jsonResponse } from "../../../lib/api/errors.js";
import { validationFailure } from "../../../lib/api/validate.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { feedDiscoveryService } from "../../../services/discovery.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const validateSchema = z.object({
  url: z.string().url("Invalid URL format"),
});

export async function action({ request }: { request: Request }) {
  return handle(async () => {
    const parsed = validateSchema.safeParse(await readJsonBody(request));
    if (!parsed.success) {
      return validationFailure(parsed.error);
    }

    const { url } = parsed.data;

    try {
      const metadata = await feedDiscoveryService.fetchFeedMetadata(url);
      const isValid = !!metadata.title;

      return jsonResponse({
        success: true,
        data: {
          valid: isValid,
          metadata: isValid ? metadata : null,
        },
      });
    } catch {
      return jsonResponse({
        success: true,
        data: {
          valid: false,
          error: "Unable to parse feed",
        },
      });
    }
  });
}
