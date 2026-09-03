import { Router } from 'express';
import { z } from 'zod';
import { getDb } from '../database';
import { folders, feeds, articles, userArticleStates } from '../database/schema';
import { eq, and, sql, isNull } from 'drizzle-orm';
import { AppError } from '../middleware/errorHandler';

const router = Router();

// Validation schemas
const createFolderSchema = z.object({
  name: z.string().min(1).max(100),
  color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional(),
  icon: z.string().optional(),
  parentId: z.string().uuid().nullable().optional(),
});

const updateFolderSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional(),
  icon: z.string().optional(),
  parentId: z.string().uuid().nullable().optional(),
});

// Get all folders with feed count
router.get('/', async (req, res, next) => {
  try {
    const db = getDb();

    // Get folders with feed and unread counts
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
        feedCount: sql<number>`COUNT(DISTINCT ${feeds.id})`.as('feedCount'),
        unreadCount: sql<number>`
          COUNT(DISTINCT ${articles.id}) FILTER (
            WHERE ${articles.id} IS NOT NULL 
            AND NOT EXISTS (
              SELECT 1 FROM ${userArticleStates} 
              WHERE ${userArticleStates.articleId} = ${articles.id} 
              AND ${userArticleStates.userId} = ${req.user!.id}
              AND ${userArticleStates.isRead} = true
            )
          )
        `.as('unreadCount'),
      })
      .from(folders)
      .leftJoin(feeds, eq(feeds.folderId, folders.id))
      .leftJoin(articles, eq(articles.feedId, feeds.id))
      .where(eq(folders.userId, req.user!.id))
      .groupBy(folders.id)
      .orderBy(folders.position, folders.name);

    // Build folder tree
    type FolderNode = typeof userFolders[number] & { children: FolderNode[] };
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

    res.json({ folders: rootFolders });
  } catch (error) {
    next(error);
  }
});

// Get single folder
router.get('/:folderId', async (req, res, next) => {
  try {
    const { folderId } = req.params;
    const db = getDb();

    const [folder] = await db
      .select()
      .from(folders)
      .where(
        and(
          eq(folders.id, folderId),
          eq(folders.userId, req.user!.id),
        ),
      )
      .limit(1);

    if (!folder) {
      throw new AppError('Folder not found', 404);
    }

    // Get feeds in folder
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
              AND ${userArticleStates.userId} = ${req.user!.id}
              AND ${userArticleStates.isRead} = true
            )
          )
        `.as('unreadCount'),
      })
      .from(feeds)
      .leftJoin(articles, eq(articles.feedId, feeds.id))
      .where(
        and(
          eq(feeds.folderId, folderId),
          eq(feeds.userId, req.user!.id),
        ),
      )
      .groupBy(feeds.id);

    res.json({
      folder,
      feeds: folderFeeds,
    });
  } catch (error) {
    next(error);
  }
});

// Create folder
router.post('/', async (req, res, next) => {
  try {
    const data = createFolderSchema.parse(req.body);
    const db = getDb();

    // Check for duplicate name at same level
    const existingFolder = await db
      .select()
      .from(folders)
      .where(
        and(
          eq(folders.userId, req.user!.id),
          eq(folders.name, data.name),
          data.parentId 
            ? eq(folders.parentId, data.parentId)
            : isNull(folders.parentId),
        ),
      )
      .limit(1);

    if (existingFolder.length > 0) {
      throw new AppError('Folder with this name already exists at this level', 409);
    }

    // Get max position
    const [maxPosition] = await db
      .select({ max: sql<number>`MAX(${folders.position})` })
      .from(folders)
      .where(eq(folders.userId, req.user!.id));

    // Create folder
    const [newFolder] = await db
      .insert(folders)
      .values({
        userId: req.user!.id,
        name: data.name,
        color: data.color,
        icon: data.icon,
        parentId: data.parentId,
        position: Number(maxPosition?.max || 0) + 1,
      })
      .returning();

    res.status(201).json({ folder: newFolder });
  } catch (error) {
    next(error);
  }
});

// Update folder
router.put('/:folderId', async (req, res, next) => {
  try {
    const { folderId } = req.params;
    const data = updateFolderSchema.parse(req.body);
    const db = getDb();

    // Check ownership
    const [existingFolder] = await db
      .select()
      .from(folders)
      .where(
        and(
          eq(folders.id, folderId),
          eq(folders.userId, req.user!.id),
        ),
      )
      .limit(1);

    if (!existingFolder) {
      throw new AppError('Folder not found', 404);
    }

    // Check for circular reference
    if (data.parentId) {
      if (data.parentId === folderId) {
        throw new AppError('Folder cannot be its own parent', 400);
      }

      // Check if new parent is a descendant
      const isDescendant = await checkIfDescendant(db, folderId, data.parentId, req.user!.id);
      if (isDescendant) {
        throw new AppError('Cannot move folder to its own descendant', 400);
      }
    }

    // Check for duplicate name at new level
    if (data.name || data.parentId !== undefined) {
      const nameToCheck = data.name || existingFolder.name;
      const parentToCheck = data.parentId !== undefined ? data.parentId : existingFolder.parentId;

      const duplicateFolder = await db
        .select()
        .from(folders)
        .where(
          and(
            eq(folders.userId, req.user!.id),
            eq(folders.name, nameToCheck),
            parentToCheck 
              ? eq(folders.parentId, parentToCheck)
              : isNull(folders.parentId),
            // Exclude current folder
            sql`${folders.id} != ${folderId}`,
          ),
        )
        .limit(1);

      if (duplicateFolder.length > 0) {
        throw new AppError('Folder with this name already exists at this level', 409);
      }
    }

    // Update folder
    const [updatedFolder] = await db
      .update(folders)
      .set({
        ...data,
        updatedAt: new Date(),
      })
      .where(eq(folders.id, folderId))
      .returning();

    res.json({ folder: updatedFolder });
  } catch (error) {
    next(error);
  }
});

// Delete folder
router.delete('/:folderId', async (req, res, next) => {
  try {
    const { folderId } = req.params;
    const db = getDb();

    // Check ownership
    const [existingFolder] = await db
      .select()
      .from(folders)
      .where(
        and(
          eq(folders.id, folderId),
          eq(folders.userId, req.user!.id),
        ),
      )
      .limit(1);

    if (!existingFolder) {
      throw new AppError('Folder not found', 404);
    }

    // Check if folder has feeds
    const [feedCount] = await db
      .select({ count: sql<number>`COUNT(*)` })
      .from(feeds)
      .where(eq(feeds.folderId, folderId));

    if (feedCount.count > 0) {
      throw new AppError('Cannot delete folder with feeds. Move or delete feeds first.', 400);
    }

    // Check if folder has subfolders
    const [subfolderCount] = await db
      .select({ count: sql<number>`COUNT(*)` })
      .from(folders)
      .where(eq(folders.parentId, folderId));

    if (subfolderCount.count > 0) {
      throw new AppError('Cannot delete folder with subfolders. Delete subfolders first.', 400);
    }

    // Delete folder
    await db
      .delete(folders)
      .where(eq(folders.id, folderId));

    res.status(204).send();
  } catch (error) {
    next(error);
  }
});

// Reorder folders
router.post('/reorder', async (req, res, next) => {
  try {
    const { folderIds } = z.object({
      folderIds: z.array(z.string().uuid()),
    }).parse(req.body);

    const db = getDb();

    // Verify ownership of all folders
    const userFolders = await db
      .select({ id: folders.id })
      .from(folders)
      .where(eq(folders.userId, req.user!.id));

    const userFolderIds = new Set(userFolders.map(f => f.id));
    const validFolderIds = folderIds.filter(id => userFolderIds.has(id));

    // Update sort order
    for (let i = 0; i < validFolderIds.length; i++) {
      await db
        .update(folders)
        .set({
          position: i + 1,
          updatedAt: new Date(),
        })
        .where(eq(folders.id, validFolderIds[i]));
    }

    res.json({ message: 'Folders reordered successfully' });
  } catch (error) {
    next(error);
  }
});

// Helper function to check if a folder is a descendant of another
async function checkIfDescendant(
  db: any,
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

export default router;