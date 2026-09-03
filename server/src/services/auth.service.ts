import { getDb } from '../database';
import { users } from '../database/schema';
import { eq } from 'drizzle-orm';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { AppError } from '../middleware/errorHandler';
import { logger } from '../utils/logger';

export interface RegisterData {
  email: string;
  username: string;
  password: string;
  firstName?: string;
  lastName?: string;
}

export interface SafeUser {
  id: string;
  email: string;
  username: string;
  role: string;
}

export class AuthService {
  async register(data: RegisterData): Promise<{ user: SafeUser; token: string }> {
    const db = getDb();

    const [existingByEmail] = await db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.email, data.email))
      .limit(1);

    if (existingByEmail) {
      throw new AppError('Email already registered', 409);
    }

    const [existingByUsername] = await db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.username, data.username))
      .limit(1);

    if (existingByUsername) {
      throw new AppError('Username already taken', 409);
    }

    const passwordHash = await bcrypt.hash(data.password, parseInt(process.env.BCRYPT_ROUNDS || '10', 10));

    const [newUser] = await db
      .insert(users)
      .values({
        email: data.email,
        username: data.username,
        passwordHash,
        firstName: data.firstName,
        lastName: data.lastName,
      })
      .returning();

    const token = this.signToken(newUser.id, newUser.email, newUser.username, newUser.role);

    logger.info(`User registered: ${newUser.email}`);

    return {
      user: {
        id: newUser.id,
        email: newUser.email,
        username: newUser.username,
        role: newUser.role,
      },
      token,
    };
  }

  async login(email: string, password: string): Promise<{ user: SafeUser; token: string }> {
    const db = getDb();

    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.email, email))
      .limit(1);

    if (!user) {
      throw new AppError('Invalid credentials', 401);
    }

    const isValid = await bcrypt.compare(password, user.passwordHash || '');
    if (!isValid) {
      throw new AppError('Invalid credentials', 401);
    }

    if (!user.isActive) {
      throw new AppError('Account is deactivated', 403);
    }

    await db
      .update(users)
      .set({ lastLoginAt: new Date() })
      .where(eq(users.id, user.id));

    const token = this.signToken(user.id, user.email, user.username, user.role);

    return {
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        role: user.role,
      },
      token,
    };
  }

  verifyToken(token: string): Record<string, unknown> | null {
    try {
      return jwt.verify(token, process.env.JWT_SECRET!) as Record<string, unknown>;
    } catch {
      return null;
    }
  }

  async changePassword(userId: string, currentPassword: string, newPassword: string): Promise<void> {
    const db = getDb();

    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.id, userId))
      .limit(1);

    if (!user) {
      throw new AppError('User not found', 404);
    }

    const isValid = await bcrypt.compare(currentPassword, user.passwordHash || '');
    if (!isValid) {
      throw new AppError('Current password is incorrect', 400);
    }

    const passwordHash = await bcrypt.hash(newPassword, parseInt(process.env.BCRYPT_ROUNDS || '10', 10));

    await getDb()
      .update(users)
      .set({ passwordHash, updatedAt: new Date() })
      .where(eq(users.id, userId));
  }

  private signToken(userId: string, email: string, username: string, role: string): string {
    return jwt.sign(
      { userId, email, username, role },
      process.env.JWT_SECRET!,
      { expiresIn: (process.env.JWT_EXPIRES_IN || '7d') as jwt.SignOptions['expiresIn'] },
    );
  }
}

export const authService = new AuthService();
