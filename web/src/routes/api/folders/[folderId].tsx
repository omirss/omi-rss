import { z } from "zod";
import { eq, and, sql, isNull } from "drizzle-orm";
import { folders, feeds, articles, userArticleStates } from "../../../data/db/schema.js";
import type { Database } from "../../../lib/api/db.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, handleLoader, jsonResponse, noContent } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { assertFolderOwned } from "../../../lib/api/folders.js";

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
      // One transaction under the same per-user advisory lock the cycle
      // trigger takes: the emptiness pre-checks and the delete commit
      // atomically, so a subfolder moved under this folder between check
      // and delete can no longer be cascade-deleted by the race.
      await db.transaction(async (tx) => {
        await tx.execute(sql`SELECT pg_advisory_xact_lock(hashtextextended(${auth.id}::text, 719))`);

        const [feedCount] = await tx
          .select({ count: sql<number>`COUNT(*)` })
          .from(feeds)
          .where(eq(feeds.folderId, folderId));

        if (Number(feedCount.count) > 0) {
          throw new AppError("Cannot delete folder with feeds. Move or delete feeds first.", 400);
        }

        const [subfolderCount] = await tx
          .select({ count: sql<number>`COUNT(*)` })
          .from(folders)
          .where(eq(folders.parentId, folderId));

        if (Number(subfolderCount.count) > 0) {
          throw new AppError("Cannot delete folder with subfolders. Delete subfolders first.", 400);
        }

        await tx
          .delete(folders)
          .where(eq(folders.id, folderId));
      });

      return noContent();
    }

    const data = updateFolderSchema.parse(await readJsonBody(request));

    if (data.parentId) {
      if (data.parentId === folderId) {
        throw new AppError("Folder cannot be its own parent", 400);
      }

      await assertFolderOwned(db, data.parentId, auth.id);

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

    try {
      const [updatedFolder] = await db
        .update(folders)
        .set({
          ...data,
          updatedAt: new Date(),
        })
        .where(eq(folders.id, folderId))
        .returning();

      return jsonResponse({ folder: updatedFolder });
    } catch (error) {
      // The omi_check_folder_parent trigger is the TOCTOU backstop for the
      // cycle pre-check above — surface its rejections as 409s.
      if (error instanceof Error && /folder (cycle detected|cannot be its own parent|hierarchy deeper)/.test(error.message)) {
        throw new AppError(error.message, 409);
      }
      throw error;
    }
  });
}

// Iterative walk with a seen-set: recursion-free, and a historical cycle in
// the table terminates with a positive answer instead of infinite recursion.
export async function checkIfDescendant(
  db: Database,
  parentId: string,
  potentialDescendantId: string,
  userId: string,
): Promise<boolean> {
  const childrenByParent = await db
    .select({ id: folders.id, parentId: folders.parentId })
    .from(folders)
    .where(eq(folders.userId, userId));

  const childrenOf = new Map<string, string[]>();
  for (const row of childrenByParent) {
    if (row.parentId === null) continue;
    const siblings = childrenOf.get(row.parentId) ?? [];
    siblings.push(row.id);
    childrenOf.set(row.parentId, siblings);
  }

  const queue = [parentId];
  const seen = new Set<string>([parentId]);
  while (queue.length > 0) {
    const current = queue.shift()!;
    if (current === potentialDescendantId) return true;
    for (const child of childrenOf.get(current) ?? []) {
      if (seen.has(child)) continue;
      seen.add(child);
      queue.push(child);
    }
  }
  return false;
}
