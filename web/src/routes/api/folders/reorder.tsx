import { z } from "zod";
import { eq } from "drizzle-orm";
import { folders } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { handle, jsonResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };
    const { folderIds } = z.object({
      folderIds: z.array(z.string().uuid()),
    }).parse(await readJsonBody(request));

    const db = await getDb();

    const userFolders = await db
      .select({ id: folders.id })
      .from(folders)
      .where(eq(folders.userId, auth.id));

    const userFolderIds = new Set(userFolders.map(f => f.id));
    const validFolderIds = folderIds.filter(id => userFolderIds.has(id));

    for (let i = 0; i < validFolderIds.length; i++) {
      await db
        .update(folders)
        .set({
          position: i + 1,
          updatedAt: new Date(),
        })
        .where(eq(folders.id, validFolderIds[i]));
    }

    return jsonResponse({ message: "Folders reordered successfully" });
  });
}
