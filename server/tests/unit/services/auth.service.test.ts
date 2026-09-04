import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} from '../../../src/services/auth.service';
import jwt from 'jsonwebtoken';

jest.mock('jsonwebtoken');

describe('auth token functions', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('signAccessToken', () => {
    it('should sign an access token with user claims', () => {
      signAccessToken('123', 'test@example.com', 'testuser', 'user');

      expect(jwt.sign).toHaveBeenCalledWith(
        { userId: '123', email: 'test@example.com', username: 'testuser', role: 'user' },
        process.env.JWT_SECRET,
        { expiresIn: process.env.JWT_EXPIRES_IN || '7d' },
      );
    });
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
});
