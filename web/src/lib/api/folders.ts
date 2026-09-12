import { and, eq } from "drizzle-orm";
import { folders } from "../../data/db/schema.js";
import type { Database } from "./db.js";
import { AppError } from "./errors.js";

// Guards folderId/parentId references against cross-tenant attachment:
// the FK on the column only proves existence, never ownership, so every
// route that accepts a folder reference must check it belongs to the caller.
export async function assertFolderOwned(db: Database, folderId: string, userId: string): Promise<void> {
  const [folder] = await db
    .select({ id: folders.id })
    .from(folders)
    .where(and(eq(folders.id, folderId), eq(folders.userId, userId)))
    .limit(1);
  if (!folder) {
    throw new AppError("Folder not found", 404);
  }
}
