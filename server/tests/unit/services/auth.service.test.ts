import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import {
  authService,
  signRefreshToken,
  verifyRefreshToken,
} from '../../../src/services/auth.service';
import { getDb } from '../../../src/database';
import { users } from '../../../src/database/schema';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';

jest.mock('../../../src/database');
jest.mock('bcrypt');
jest.mock('jsonwebtoken');

describe('AuthService', () => {
  let mockDb: any;

  beforeEach(() => {
    jest.clearAllMocks();
    mockDb = {
      select: jest.fn().mockReturnThis(),
      from: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      limit: jest.fn<any>().mockResolvedValue([]),
      insert: jest.fn().mockReturnThis(),
      values: jest.fn().mockReturnThis(),
      returning: jest.fn<any>().mockResolvedValue([]),
      update: jest.fn().mockReturnThis(),
      set: jest.fn().mockReturnThis(),
    };
    (getDb as jest.Mock).mockReturnValue(mockDb);
  });

  describe('refresh tokens', () => {
    it('should sign a refresh token with a refresh type claim and 30d expiry', () => {
      signRefreshToken('123');

      expect(jwt.sign).toHaveBeenCalledWith(
        { userId: '123', type: 'refresh' },
        process.env.JWT_SECRET,
        { expiresIn: '30d' },
      );
    });

    it('should verify a valid refresh token', () => {
      (jwt.verify as jest.Mock).mockReturnValue({ userId: '123', type: 'refresh' });

      const result = verifyRefreshToken('refreshtoken');

      expect(result).toEqual({ userId: '123' });
      expect(jwt.verify).toHaveBeenCalledWith('refreshtoken', process.env.JWT_SECRET);
    });

    it('should reject an access token used as a refresh token', () => {
      (jwt.verify as jest.Mock).mockReturnValue({ userId: '123', email: 'test@example.com', role: 'user' });

      expect(verifyRefreshToken('accesstoken')).toBeNull();
    });

    it('should reject a refresh token without a userId', () => {
      (jwt.verify as jest.Mock).mockReturnValue({ type: 'refresh' });

      expect(verifyRefreshToken('refreshtoken')).toBeNull();
    });

    it('should return null for an invalid token', () => {
      (jwt.verify as jest.Mock).mockImplementation(() => {
        throw new Error('Invalid token');
      });

      expect(verifyRefreshToken('invalidtoken')).toBeNull();
    });
  });

  describe('register', () => {
    it('should register a new user successfully', async () => {
      const userData = {
        email: 'test@example.com',
        username: 'testuser',
        password: 'password123',
      };

      mockDb.limit.mockResolvedValueOnce([]); // No existing user
      (bcrypt.hash as any).mockResolvedValue('hashedPassword');
      mockDb.returning.mockResolvedValueOnce([{
        id: '123',
        email: userData.email,
        username: userData.username,
        role: 'user',
      }]);
      (jwt.sign as jest.Mock).mockReturnValue('token123');

      const result = await authService.register(userData);

      expect(result).toHaveProperty('user');
      expect(result).toHaveProperty('token', 'token123');
      expect(result.user.email).toBe(userData.email);
      expect(bcrypt.hash).toHaveBeenCalledWith(userData.password, 10);
    });

    it('should throw error if email already exists', async () => {
      const userData = {
        email: 'existing@example.com',
        username: 'testuser',
        password: 'password123',
      };

      mockDb.limit.mockResolvedValueOnce([{ id: '123' }]); // Existing user

      await expect(authService.register(userData)).rejects.toThrow('Email already registered');
    });

    it('should throw error if username already exists', async () => {
      const userData = {
        email: 'test@example.com',
        username: 'existinguser',
        password: 'password123',
      };

      mockDb.limit
        .mockResolvedValueOnce([]) // No email conflict
        .mockResolvedValueOnce([{ id: '123' }]); // Username exists

      await expect(authService.register(userData)).rejects.toThrow('Username already taken');
    });
  });

  describe('login', () => {
    it('should login with valid credentials', async () => {
      const credentials = {
        email: 'test@example.com',
        password: 'password123',
      };

      const mockUser = {
        id: '123',
        email: credentials.email,
        username: 'testuser',
        passwordHash: 'hashedPassword',
        isActive: true,
        role: 'user',
      };

      mockDb.limit.mockResolvedValueOnce([mockUser]);
      (bcrypt.compare as any).mockResolvedValue(true);
      (jwt.sign as jest.Mock).mockReturnValue('token123');

      const result = await authService.login(credentials.email, credentials.password);

      expect(result).toHaveProperty('user');
      expect(result).toHaveProperty('token', 'token123');
      expect(result.user.id).toBe(mockUser.id);
      expect(bcrypt.compare).toHaveBeenCalledWith(credentials.password, mockUser.passwordHash);
    });

    it('should throw error for invalid email', async () => {
      mockDb.limit.mockResolvedValueOnce([]); // No user found

      await expect(authService.login('invalid@example.com', 'password')).rejects.toThrow('Invalid credentials');
    });

    it('should throw error for wrong password', async () => {
      const mockUser = {
        id: '123',
        passwordHash: 'hashedPassword',
        isActive: true,
      };

      mockDb.limit.mockResolvedValueOnce([mockUser]);
      (bcrypt.compare as any).mockResolvedValue(false);

      await expect(authService.login('test@example.com', 'wrongpassword')).rejects.toThrow('Invalid credentials');
    });

    it('should throw error for inactive account', async () => {
      const mockUser = {
        id: '123',
        passwordHash: 'hashedPassword',
        isActive: false,
      };

      mockDb.limit.mockResolvedValueOnce([mockUser]);
      (bcrypt.compare as any).mockResolvedValue(true);

      await expect(authService.login('test@example.com', 'password')).rejects.toThrow('Account is deactivated');
    });
  });

  describe('verifyToken', () => {
    it('should verify valid token', async () => {
      const mockPayload = {
        id: '123',
        email: 'test@example.com',
        role: 'user',
      };

      (jwt.verify as jest.Mock).mockReturnValue(mockPayload);

      const result = await authService.verifyToken('validtoken');

      expect(result).toEqual(mockPayload);
      expect(jwt.verify).toHaveBeenCalledWith('validtoken', process.env.JWT_SECRET);
    });

    it('should return null for invalid token', async () => {
      (jwt.verify as jest.Mock).mockImplementation(() => {
        throw new Error('Invalid token');
      });

      const result = await authService.verifyToken('invalidtoken');

      expect(result).toBeNull();
    });
  });

  describe('changePassword', () => {
    it('should change password successfully', async () => {
      const userId = '123';
      const oldPassword = 'oldpass';
      const newPassword = 'newpass';

      const mockUser = {
        id: userId,
        passwordHash: 'oldHashedPassword',
      };

      mockDb.limit.mockResolvedValueOnce([mockUser]);
      (bcrypt.compare as any).mockResolvedValue(true);
      (bcrypt.hash as any).mockResolvedValue('newHashedPassword');
      
      const mockUpdate = {
        update: jest.fn().mockReturnThis(),
        set: jest.fn().mockReturnThis(),
        where: jest.fn().mockReturnThis(),
      };
      (getDb as jest.Mock).mockReturnValueOnce(mockDb).mockReturnValueOnce(mockUpdate);

      await authService.changePassword(userId, oldPassword, newPassword);

      expect(bcrypt.compare).toHaveBeenCalledWith(oldPassword, mockUser.passwordHash);
      expect(bcrypt.hash).toHaveBeenCalledWith(newPassword, 10);
      expect(mockUpdate.update).toHaveBeenCalledWith(users);
    });

    it('should throw error for incorrect old password', async () => {
      const mockUser = {
        id: '123',
        passwordHash: 'hashedPassword',
      };

      mockDb.limit.mockResolvedValueOnce([mockUser]);
      (bcrypt.compare as any).mockResolvedValue(false);

      await expect(authService.changePassword('123', 'wrongold', 'newpass')).rejects.toThrow('Current password is incorrect');
    });
  });
});