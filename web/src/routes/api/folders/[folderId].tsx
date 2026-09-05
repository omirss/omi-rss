import { z } from "zod";
import { eq, and, sql, isNull } from "drizzle-orm";
import { folders, feeds, articles, userArticleStates } from "../../../data/db/schema.js";
import type { Database } from "../../../lib/api/db.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, handleLoader, jsonResponse, noContent } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const updateFolderSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional(),
  icon: z.string().optional(),
  parentId: z.string().uuid().nullable().optional(),
});

export async function loader({ params, context }: { params: Record<string, string>; context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };
    const { folderId } = params;
    const db = await getDb();

    const [folder] = await db
      .select()
      .from(folders)
      .where(
        and(
          eq(folders.id, folderId),
          eq(folders.userId, auth.id),
        ),
      )
      .limit(1);

    if (!folder) {
      throw new AppError("Folder not found", 404);
    }

    const folderFeeds = await db
      .select({
        id: feeds.id,
        title: feeds.title,
        customTitle: feeds.customTitle,
        favicon: feeds.favicon,
        unreadCount: sql<number>`
          COUNT(DISTINCT ${articles.id}) FILTER (
            WHERE NOT EXISTS (
              SELECT 1 FROM ${userArticleStates}
              WHERE ${userArticleStates.articleId} = ${articles.id}
              AND ${userArticleStates.userId} = ${auth.id}
              AND ${userArticleStates.isRead} = true
            )
          )
        `.as("unreadCount"),
      })
      .from(feeds)
      .leftJoin(articles, eq(articles.feedId, feeds.id))
      .where(
        and(
          eq(feeds.folderId, folderId),
          eq(feeds.userId, auth.id),
        ),
      )
      .groupBy(feeds.id);

    return jsonResponse({
      folder,
      feeds: folderFeeds.map(f => ({
        ...f,
        unreadCount: Number(f.unreadCount),
      })),
    });
  });
}

export async function action({ request, params, context }: { request: Request; params: Record<string, string>; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };
    const { folderId } = params;
    const db = await getDb();

    const [existingFolder] = await db
      .select()
      .from(folders)
      .where(
        and(
          eq(folders.id, folderId),
          eq(folders.userId, auth.id),
        ),
      )
      .limit(1);

    if (!existingFolder) {
      throw new AppError("Folder not found", 404);
    }

    if (request.method === "DELETE") {
      const [feedCount] = await db
        .select({ count: sql<number>`COUNT(*)` })
        .from(feeds)
        .where(eq(feeds.folderId, folderId));

      if (Number(feedCount.count) > 0) {
        throw new AppError("Cannot delete folder with feeds. Move or delete feeds first.", 400);
      }

      const [subfolderCount] = await db
        .select({ count: sql<number>`COUNT(*)` })
        .from(folders)
        .where(eq(folders.parentId, folderId));

      if (Number(subfolderCount.count) > 0) {
        throw new AppError("Cannot delete folder with subfolders. Delete subfolders first.", 400);
      }

      await db
        .delete(folders)
        .where(eq(folders.id, folderId));

      return noContent();
    }

    const data = updateFolderSchema.parse(await readJsonBody(request));

    if (data.parentId) {
      if (data.parentId === folderId) {
        throw new AppError("Folder cannot be its own parent", 400);
      }

      const isDescendant = await checkIfDescendant(db, folderId, data.parentId, auth.id);
      if (isDescendant) {
        throw new AppError("Cannot move folder to its own descendant", 400);
      }
    }

    if (data.name || data.parentId !== undefined) {
      const nameToCheck = data.name || existingFolder.name;
      const parentToCheck = data.parentId !== undefined ? data.parentId : existingFolder.parentId;

      const duplicateFolder = await db
        .select()
        .from(folders)
        .where(
          and(
            eq(folders.userId, auth.id),
            eq(folders.name, nameToCheck),
            parentToCheck
              ? eq(folders.parentId, parentToCheck)
              : isNull(folders.parentId),
            sql`${folders.id} != ${folderId}`,
          ),
        )
        .limit(1);

      if (duplicateFolder.length > 0) {
        throw new AppError("Folder with this name already exists at this level", 409);
      }
    }

    const [updatedFolder] = await db
      .update(folders)
      .set({
        ...data,
        updatedAt: new Date(),
      })
      .where(eq(folders.id, folderId))
      .returning();

    return jsonResponse({ folder: updatedFolder });
  });
}

async function checkIfDescendant(
  db: Database,
  parentId: string,
  potentialDescendantId: string,
  userId: string,
): Promise<boolean> {
  const children = await db
    .select({ id: folders.id, parentId: folders.parentId })
    .from(folders)
    .where(
      and(
        eq(folders.userId, userId),
        eq(folders.parentId, parentId),
      ),
    );

  for (const child of children) {
    if (child.id === potentialDescendantId) {
      return true;
    }
    const isChildDescendant = await checkIfDescendant(db, child.id, potentialDescendantId, userId);
    if (isChildDescendant) {
      return true;
    }
  }

  return false;
}
