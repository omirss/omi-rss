import { Router } from 'express';
import { z } from 'zod';
import { getDb } from '../database';
import { users } from '../database/schema';
import { eq } from 'drizzle-orm';
import { AppError } from '../middleware/errorHandler';
import bcrypt from 'bcrypt';
import multer from 'multer';
import sharp from 'sharp';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';

const router = Router();

// Multer configuration for avatar upload
const storage = multer.memoryStorage();
const upload = multer({
  storage,
  limits: {
    fileSize: 5 * 1024 * 1024, // 5MB
  },
  fileFilter: (req, file, cb) => {
    const allowedTypes = /jpeg|jpg|png|gif|webp/;
    const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
    const mimetype = allowedTypes.test(file.mimetype);
    
    if (mimetype && extname) {
      return cb(null, true);
    } else {
      cb(new Error('Only image files are allowed'));
    }
  },
});

// Validation schemas
const updateProfileSchema = z.object({
  firstName: z.string().optional(),
  lastName: z.string().optional(),
  username: z.string().min(3).max(50).optional(),
});

const updatePasswordSchema = z.object({
  currentPassword: z.string(),
  newPassword: z.string().min(8).max(100),
});

const updateSettingsSchema = z.object({
  settings: z.record(z.any()),
});

// Get current user profile
router.get('/me', async (req, res, next) => {
  try {
    const db = getDb();
    
    const [user] = await db
      .select({
        id: users.id,
        email: users.email,
        username: users.username,
        firstName: users.firstName,
        lastName: users.lastName,
        avatarUrl: users.avatarUrl,
        role: users.role,
        emailVerified: users.emailVerified,
        settings: users.settings,
        createdAt: users.createdAt,
        updatedAt: users.updatedAt,
        lastLoginAt: users.lastLoginAt,
      })
      .from(users)
      .where(eq(users.id, req.user!.id))
      .limit(1);

    if (!user) {
      throw new AppError('User not found', 404);
    }

    res.json({ user });
  } catch (error) {
    next(error);
  }
});

// Update user profile
router.put('/me', async (req, res, next) => {
  try {
    const data = updateProfileSchema.parse(req.body);
    const db = getDb();

    // Check if username is already taken
    if (data.username) {
      const [existingUser] = await db
        .select()
        .from(users)
        .where(eq(users.username, data.username))
        .limit(1);

      if (existingUser && existingUser.id !== req.user!.id) {
        throw new AppError('Username already taken', 409);
      }
    }

    // Update user
    const [updatedUser] = await db
      .update(users)
      .set({
        ...data,
        updatedAt: new Date(),
      })
      .where(eq(users.id, req.user!.id))
      .returning({
        id: users.id,
        email: users.email,
        username: users.username,
        firstName: users.firstName,
        lastName: users.lastName,
        avatarUrl: users.avatarUrl,
      });

    res.json({ user: updatedUser });
  } catch (error) {
    next(error);
  }
});

// Update password
router.put('/me/password', async (req, res, next) => {
  try {
    const data = updatePasswordSchema.parse(req.body);
    const db = getDb();

    // Get current user
    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.id, req.user!.id))
      .limit(1);

    if (!user) {
      throw new AppError('User not found', 404);
    }

    // Verify current password
    const isValidPassword = await bcrypt.compare(data.currentPassword, user.passwordHash || '');
    if (!isValidPassword) {
      throw new AppError('Current password is incorrect', 401);
    }

    // Hash new password
    const passwordHash = await bcrypt.hash(data.newPassword, parseInt(process.env.BCRYPT_ROUNDS || '10'));

    // Update password
    await db
      .update(users)
      .set({
        passwordHash,
        updatedAt: new Date(),
      })
      .where(eq(users.id, req.user!.id));

    res.json({ message: 'Password updated successfully' });
  } catch (error) {
    next(error);
  }
});

// Upload avatar
router.post('/me/avatar', upload.single('avatar'), async (req, res, next) => {
  try {
    if (!req.file) {
      throw new AppError('No file uploaded', 400);
    }

    const db = getDb();
    
    // Generate unique filename
    const filename = `${uuidv4()}.webp`;
    const filepath = path.join(process.env.UPLOAD_DIR || './uploads', 'avatars', filename);

    // Process and save image
    await sharp(req.file.buffer)
      .resize(256, 256, {
        fit: 'cover',
        position: 'center',
      })
      .webp({ quality: 80 })
      .toFile(filepath);

    // Update user avatar
    const avatarUrl = `/uploads/avatars/${filename}`;
    const [updatedUser] = await db
      .update(users)
      .set({
        avatarUrl,
        updatedAt: new Date(),
      })
      .where(eq(users.id, req.user!.id))
      .returning({
        id: users.id,
        avatarUrl: users.avatarUrl,
      });

    res.json({ 
      user: updatedUser,
      avatarUrl,
    });
  } catch (error) {
    next(error);
  }
});

// Update user settings
router.put('/me/settings', async (req, res, next) => {
  try {
    const data = updateSettingsSchema.parse(req.body);
    const db = getDb();

    // Get current settings
    const [user] = await db
      .select({ settings: users.settings })
      .from(users)
      .where(eq(users.id, req.user!.id))
      .limit(1);

    if (!user) {
      throw new AppError('User not found', 404);
    }

    // Merge settings
    const newSettings = {
      ...(user.settings as object || {}),
      ...data.settings,
    };

    // Update settings
    const [updatedUser] = await db
      .update(users)
      .set({
        settings: newSettings,
        updatedAt: new Date(),
      })
      .where(eq(users.id, req.user!.id))
      .returning({
        id: users.id,
        settings: users.settings,
      });

    res.json({ 
      user: updatedUser,
      settings: updatedUser.settings,
    });
  } catch (error) {
    next(error);
  }
});

// Delete account
router.delete('/me', async (req, res, next) => {
  try {
    const { password } = req.body;
    
    if (!password) {
      throw new AppError('Password required to delete account', 400);
    }

    const db = getDb();

    // Get user
    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.id, req.user!.id))
      .limit(1);

    if (!user) {
      throw new AppError('User not found', 404);
    }

    // Verify password
    const isValidPassword = await bcrypt.compare(password, user.passwordHash || '');
    if (!isValidPassword) {
      throw new AppError('Password is incorrect', 401);
    }

    // Delete user (cascades to all related data)
    await db
      .delete(users)
      .where(eq(users.id, req.user!.id));

    res.status(204).send();
  } catch (error) {
    next(error);
  }
});

export default router;