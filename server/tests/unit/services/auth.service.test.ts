import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import { authService } from '../../../src/services/auth.service';
import { getDb } from '../../../src/database';
import { users } from '../../../src/database/schema';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';

jest.mock('../../../src/database');
jest.mock('bcrypt');
jest.mock('jsonwebtoken');

describe('AuthService', () => {
  const mockDb = {
    select: jest.fn().mockReturnThis(),
    from: jest.fn().mockReturnThis(),
    where: jest.fn().mockReturnThis(),
    limit: jest.fn().mockReturnThis(),
    insert: jest.fn().mockReturnThis(),
    values: jest.fn().mockReturnThis(),
    returning: jest.fn().mockReturnThis(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (getDb as jest.Mock).mockReturnValue(mockDb);
  });

  describe('register', () => {
    it('should register a new user successfully', async () => {
      const userData = {
        email: 'test@example.com',
        username: 'testuser',
        password: 'password123',
      };

      mockDb.limit.mockResolvedValueOnce([]); // No existing user
      (bcrypt.hash as jest.Mock).mockResolvedValue('hashedPassword');
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
      (bcrypt.compare as jest.Mock).mockResolvedValue(true);
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
      (bcrypt.compare as jest.Mock).mockResolvedValue(false);

      await expect(authService.login('test@example.com', 'wrongpassword')).rejects.toThrow('Invalid credentials');
    });

    it('should throw error for inactive account', async () => {
      const mockUser = {
        id: '123',
        passwordHash: 'hashedPassword',
        isActive: false,
      };

      mockDb.limit.mockResolvedValueOnce([mockUser]);
      (bcrypt.compare as jest.Mock).mockResolvedValue(true);

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
      (bcrypt.compare as jest.Mock).mockResolvedValue(true);
      (bcrypt.hash as jest.Mock).mockResolvedValue('newHashedPassword');
      
      const mockUpdate = {
        update: jest.fn().mockReturnThis(),
        set: jest.fn().mockReturnThis(),
        where: jest.fn().mockReturnThis(),
      };
      (getDb as jest.Mock).mockReturnValueOnce(mockUpdate);

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
      (bcrypt.compare as jest.Mock).mockResolvedValue(false);

      await expect(authService.changePassword('123', 'wrongold', 'newpass')).rejects.toThrow('Current password is incorrect');
    });
  });
});