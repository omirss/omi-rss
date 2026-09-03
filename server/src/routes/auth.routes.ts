import { Router } from 'express';
import { z } from 'zod';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { getDb } from '../database';
import { users, oauthProviders } from '../database/schema';
import { eq, or } from 'drizzle-orm';
import { AppError } from '../middleware/errorHandler';
import { authRateLimiter } from '../middleware/rateLimiter';
import { sendEmail } from '../services/email.service';
import { generateToken } from '../utils/tokens';
import { logger } from '../utils/logger';

const router = Router();

// Validation schemas
const registerSchema = z.object({
  email: z.string().email(),
  username: z.string().min(3).max(50),
  password: z.string().min(8).max(100),
  firstName: z.string().optional(),
  lastName: z.string().optional(),
});

const loginSchema = z.object({
  emailOrUsername: z.string(),
  password: z.string(),
});

const forgotPasswordSchema = z.object({
  email: z.string().email(),
});

const resetPasswordSchema = z.object({
  token: z.string(),
  password: z.string().min(8).max(100),
});

// Register endpoint
router.post('/register', async (req, res, next) => {
  try {
    // Apply rate limiting
    await authRateLimiter.consume(req.ip);

    // Validate request body
    const data = registerSchema.parse(req.body);

    const db = getDb();

    // Check if user already exists
    const [existingUser] = await db
      .select()
      .from(users)
      .where(or(eq(users.email, data.email), eq(users.username, data.username)))
      .limit(1);

    if (existingUser) {
      throw new AppError('User already exists', 409);
    }

    // Hash password
    const passwordHash = await bcrypt.hash(data.password, parseInt(process.env.BCRYPT_ROUNDS || '10'));

    // Generate email verification token
    const emailVerificationToken = generateToken();

    // Create user
    const [newUser] = await db
      .insert(users)
      .values({
        email: data.email,
        username: data.username,
        passwordHash,
        firstName: data.firstName,
        lastName: data.lastName,
        emailVerificationToken,
      })
      .returning({
        id: users.id,
        email: users.email,
        username: users.username,
      });

    // Send verification email
    await sendEmail({
      to: data.email,
      subject: 'Verify your Omi RSS account',
      template: 'email-verification',
      data: {
        username: data.username,
        verificationUrl: `${process.env.FRONTEND_URL}/verify-email?token=${emailVerificationToken}`,
      },
    });

    // Generate JWT
    const token = jwt.sign(
      {
        userId: newUser.id,
        email: newUser.email,
        username: newUser.username,
        role: 'user',
      },
      process.env.JWT_SECRET!,
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );

    logger.info(`New user registered: ${newUser.email}`);

    res.status(201).json({
      message: 'Registration successful. Please check your email to verify your account.',
      token,
      user: newUser,
    });
  } catch (error) {
    next(error);
  }
});

// Login endpoint
router.post('/login', async (req, res, next) => {
  try {
    // Apply rate limiting
    await authRateLimiter.consume(req.ip);

    // Validate request body
    const data = loginSchema.parse(req.body);

    const db = getDb();

    // Find user by email or username
    const [user] = await db
      .select()
      .from(users)
      .where(
        or(
          eq(users.email, data.emailOrUsername),
          eq(users.username, data.emailOrUsername)
        )
      )
      .limit(1);

    if (!user) {
      throw new AppError('Invalid credentials', 401);
    }

    // Check if account is active
    if (!user.isActive) {
      throw new AppError('Account is disabled', 401);
    }

    // Verify password
    const isValidPassword = await bcrypt.compare(data.password, user.passwordHash || '');
    if (!isValidPassword) {
      throw new AppError('Invalid credentials', 401);
    }

    // Update last login
    await db
      .update(users)
      .set({ lastLoginAt: new Date() })
      .where(eq(users.id, user.id));

    // Generate JWT
    const token = jwt.sign(
      {
        userId: user.id,
        email: user.email,
        username: user.username,
        role: user.role,
      },
      process.env.JWT_SECRET!,
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );

    logger.info(`User logged in: ${user.email}`);

    res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        firstName: user.firstName,
        lastName: user.lastName,
        avatarUrl: user.avatarUrl,
        role: user.role,
        emailVerified: user.emailVerified,
        settings: user.settings,
      },
    });
  } catch (error) {
    next(error);
  }
});

// Verify email endpoint
router.get('/verify-email/:token', async (req, res, next) => {
  try {
    const { token } = req.params;

    const db = getDb();

    // Find user by token
    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.emailVerificationToken, token))
      .limit(1);

    if (!user) {
      throw new AppError('Invalid verification token', 400);
    }

    // Update user
    await db
      .update(users)
      .set({
        emailVerified: true,
        emailVerificationToken: null,
      })
      .where(eq(users.id, user.id));

    logger.info(`Email verified for user: ${user.email}`);

    res.json({ message: 'Email verified successfully' });
  } catch (error) {
    next(error);
  }
});

// Forgot password endpoint
router.post('/forgot-password', async (req, res, next) => {
  try {
    // Apply rate limiting
    await authRateLimiter.consume(req.ip);

    // Validate request body
    const data = forgotPasswordSchema.parse(req.body);

    const db = getDb();

    // Find user by email
    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.email, data.email))
      .limit(1);

    if (!user) {
      // Don't reveal if user exists
      res.json({ message: 'If an account exists, a password reset email has been sent.' });
      return;
    }

    // Generate reset token
    const resetToken = generateToken();
    const resetExpires = new Date(Date.now() + 3600000); // 1 hour

    // Update user
    await db
      .update(users)
      .set({
        passwordResetToken: resetToken,
        passwordResetExpires: resetExpires,
      })
      .where(eq(users.id, user.id));

    // Send reset email
    await sendEmail({
      to: user.email,
      subject: 'Reset your Omi RSS password',
      template: 'password-reset',
      data: {
        username: user.username,
        resetUrl: `${process.env.FRONTEND_URL}/reset-password?token=${resetToken}`,
      },
    });

    logger.info(`Password reset requested for: ${user.email}`);

    res.json({ message: 'If an account exists, a password reset email has been sent.' });
  } catch (error) {
    next(error);
  }
});

// Reset password endpoint
router.post('/reset-password', async (req, res, next) => {
  try {
    // Validate request body
    const data = resetPasswordSchema.parse(req.body);

    const db = getDb();

    // Find user by token
    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.passwordResetToken, data.token))
      .limit(1);

    if (!user || !user.passwordResetExpires || user.passwordResetExpires < new Date()) {
      throw new AppError('Invalid or expired reset token', 400);
    }

    // Hash new password
    const passwordHash = await bcrypt.hash(data.password, parseInt(process.env.BCRYPT_ROUNDS || '10'));

    // Update user
    await db
      .update(users)
      .set({
        passwordHash,
        passwordResetToken: null,
        passwordResetExpires: null,
      })
      .where(eq(users.id, user.id));

    logger.info(`Password reset for user: ${user.email}`);

    res.json({ message: 'Password reset successfully' });
  } catch (error) {
    next(error);
  }
});

// Refresh token endpoint
router.post('/refresh', async (req, res, next) => {
  try {
    const { refreshToken } = req.body;

    if (!refreshToken) {
      throw new AppError('Refresh token required', 400);
    }

    // Verify refresh token
    const decoded = jwt.verify(refreshToken, process.env.JWT_SECRET!) as any;

    const db = getDb();

    // Get fresh user data
    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.id, decoded.userId))
      .limit(1);

    if (!user || !user.isActive) {
      throw new AppError('Invalid refresh token', 401);
    }

    // Generate new access token
    const token = jwt.sign(
      {
        userId: user.id,
        email: user.email,
        username: user.username,
        role: user.role,
      },
      process.env.JWT_SECRET!,
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );

    res.json({ token });
  } catch (error) {
    next(error);
  }
});

// OAuth callback handler
router.get('/oauth/:provider/callback', async (req, res, next) => {
  try {
    const { provider } = req.params;
    const { code, state } = req.query;

    // Handle OAuth callback based on provider
    // This would integrate with passport strategies

    res.redirect(`${process.env.FRONTEND_URL}/auth/callback?provider=${provider}`);
  } catch (error) {
    next(error);
  }
});

export default router;