import { handle, jsonResponse } from "../../../../lib/api/errors.js";
import { requireAuth } from "../../../../lib/api/auth.js";
import { feedDiscoveryService } from "../../../../services/discovery.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

// Multer equivalent of the Express upload.single('file') memory storage:
// the Neutron dev server buffers the request body into a standard web
// Request, so request.formData() parses multipart natively. Same 5 MB cap.
const MAX_OPML_SIZE = 5 * 1024 * 1024;

export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };

    let form: FormData;
    try {
      form = await request.formData();
    } catch {
      return jsonResponse({
        success: false,
        error: "No file uploaded",
      }, 400);
    }

    const file = form.get("file");
    if (!(file instanceof File) || file.size === 0) {
      return jsonResponse({
        success: false,
        error: "No file uploaded",
      }, 400);
    }

    if (file.size > MAX_OPML_SIZE) {
      return jsonResponse({
        success: false,
        error: "File too large",
        timestamp: new Date().toISOString(),
      }, 500);
    }

    const opmlContent = Buffer.from(await file.arrayBuffer()).toString("utf-8");
    const result = await feedDiscoveryService.importOPML(auth.id, opmlContent);

    return jsonResponse({
      success: true,
      data: result,
    });
  });
}
