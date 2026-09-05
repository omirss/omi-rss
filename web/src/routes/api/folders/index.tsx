import { z } from "zod";
import { eq, and, sql, isNull } from "drizzle-orm";
import { folders, feeds, articles, userArticleStates } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, handleLoader, jsonResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const createFolderSchema = z.object({
  name: z.string().min(1).max(100),
  color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional(),
  icon: z.string().optional(),
  parentId: z.string().uuid().nullable().optional(),
});

export async function loader({ context }: { context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };
    const db = await getDb();

    const userFolders = await db
      .select({
        id: folders.id,
        name: folders.name,
        color: folders.color,
        icon: folders.icon,
        parentId: folders.parentId,
        position: folders.position,
        createdAt: folders.createdAt,
        updatedAt: folders.updatedAt,
        feedCount: sql<number>`COUNT(DISTINCT ${feeds.id})`.as("feedCount"),
        unreadCount: sql<number>`
          COUNT(DISTINCT ${articles.id}) FILTER (
            WHERE ${articles.id} IS NOT NULL
            AND NOT EXISTS (
              SELECT 1 FROM ${userArticleStates}
              WHERE ${userArticleStates.articleId} = ${articles.id}
              AND ${userArticleStates.userId} = ${auth.id}
              AND ${userArticleStates.isRead} = true
            )
          )
        `.as("unreadCount"),
      })
      .from(folders)
      .leftJoin(feeds, eq(feeds.folderId, folders.id))
      .leftJoin(articles, eq(articles.feedId, feeds.id))
      .where(eq(folders.userId, auth.id))
      .groupBy(folders.id)
      .orderBy(folders.position, folders.name);

    type FolderNode = (typeof userFolders)[number] & { children: FolderNode[] };
    const folderMap = new Map<string, FolderNode>(userFolders.map(f => [f.id, { ...f, children: [] }]));
    const rootFolders: FolderNode[] = [];

    userFolders.forEach(folder => {
      if (folder.parentId && folderMap.has(folder.parentId)) {
        const parent = folderMap.get(folder.parentId)!;
        const child = folderMap.get(folder.id);
        if (parent && child) {
          parent.children.push(child);
        }
      } else if (!folder.parentId) {
        const root = folderMap.get(folder.id);
        if (root) {
          rootFolders.push(root);
        }
      }
    });

    return jsonResponse({ folders: rootFolders });
  });
}

export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };
    const data = createFolderSchema.parse(await readJsonBody(request));
    const db = await getDb();

    const existingFolder = await db
      .select()
      .from(folders)
      .where(
        and(
          eq(folders.userId, auth.id),
          eq(folders.name, data.name),
          data.parentId
            ? eq(folders.parentId, data.parentId)
            : isNull(folders.parentId),
        ),
      )
      .limit(1);

    if (existingFolder.length > 0) {
      throw new AppError("Folder with this name already exists at this level", 409);
    }

    const [maxPosition] = await db
      .select({ max: sql<number>`MAX(${folders.position})` })
      .from(folders)
      .where(eq(folders.userId, auth.id));

    const [newFolder] = await db
      .insert(folders)
      .values({
        userId: auth.id,
        name: data.name,
        color: data.color,
        icon: data.icon,
        parentId: data.parentId,
        position: Number(maxPosition?.max || 0) + 1,
      })
      .returning();

    return jsonResponse({ folder: newFolder }, 201);
  });
}
