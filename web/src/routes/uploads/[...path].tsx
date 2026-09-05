import path from "node:path";
import fs from "node:fs/promises";
import { handleLoader } from "../../lib/api/errors.js";

export const config = { mode: "app" };

// Port of the Express app.use('/uploads', express.static(...)) — avatars and
// other user uploads are public (no auth), served from UPLOAD_DIR with
// express-static content types and a 404 for anything outside the directory
// or missing on disk. Works in dev and prod since it goes through the
// normal route table instead of a dev-server-only static middleware.

// v0.3.1: .svg dropped from the map — SVG uploads execute script in the
// origin context and uploads are served without auth; avatars are converted
// to webp server-side anyway, so nothing legitimate serves as svg.
const MIME_TYPES: Record<string, string> = {
  ".jpeg": "image/jpeg",
  ".jpg": "image/jpeg",
  ".png": "image/png",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
  ".avif": "image/avif",
};

function notFound(): Response {
  return new Response("Not Found", {
    status: 404,
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}

export async function loader({ request }: { request: Request }) {
  return handleLoader(async () => {
    const url = new URL(request.url);
    const relative = decodeURIComponent(url.pathname.replace(/^\/uploads\/?/, ""));
    if (!relative || relative.includes("\0")) {
      return notFound();
    }

    const uploadDir = path.resolve(process.env.UPLOAD_DIR || "./uploads");
    const filePath = path.resolve(uploadDir, relative);
    if (!filePath.startsWith(uploadDir + path.sep)) {
      return notFound();
    }

    let content: Buffer;
    try {
      content = await fs.readFile(filePath);
    } catch {
      return notFound();
    }

    const contentType = MIME_TYPES[path.extname(filePath).toLowerCase()] || "application/octet-stream";
    return new Response(new Uint8Array(content), {
      status: 200,
      headers: { "Content-Type": contentType },
    });
  });
}
