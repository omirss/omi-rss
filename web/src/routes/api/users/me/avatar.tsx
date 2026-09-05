import path from "node:path";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import sharp from "sharp";
import { eq } from "drizzle-orm";
import { users } from "../../../../data/db/schema.js";
import { getDb } from "../../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../../lib/api/errors.js";
import { requireAuth } from "../../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

// Multer equivalent: the Neutron dev server buffers the request body into a
// standard web Request, so request.formData() parses multipart natively.
// Same file filter (extension + mimetype) and size limit as the Express route.

const ALLOWED_TYPES = /jpeg|jpg|png|gif|webp/;

export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };

    let form: FormData;
    try {
      form = await request.formData();
    } catch {
      throw new AppError("Only image files are allowed", 500);
    }

    const file = form.get("avatar");
    if (!(file instanceof File) || file.size === 0) {
      throw new AppError("No file uploaded", 400);
    }

    const extname = path.extname(file.name || "").toLowerCase();
    if (!(ALLOWED_TYPES.test(file.type) && ALLOWED_TYPES.test(extname))) {
      throw new AppError("Only image files are allowed", 500);
    }

    if (file.size > parseInt(process.env.MAX_FILE_SIZE || "5242880", 10)) {
      throw new AppError("File too large", 500);
    }

    const db = await getDb();

    const filename = `${crypto.randomUUID()}.webp`;
    const uploadDir = process.env.UPLOAD_DIR || "./uploads";
    const filepath = path.join(uploadDir, "avatars", filename);

    await fs.mkdir(path.join(uploadDir, "avatars"), { recursive: true });

    await sharp(Buffer.from(await file.arrayBuffer()))
      .resize(256, 256, {
        fit: "cover",
        position: "center",
      })
      .webp({ quality: 80 })
      .toFile(filepath);

    const avatarUrl = `/uploads/avatars/${filename}`;
    const [updatedUser] = await db
      .update(users)
      .set({
        avatarUrl,
        updatedAt: new Date(),
      })
      .where(eq(users.id, auth.id))
      .returning({
        id: users.id,
        avatarUrl: users.avatarUrl,
      });

    return jsonResponse({
      user: updatedUser,
      avatarUrl,
    });
  });
}
