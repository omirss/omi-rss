import { describe, it, expect, beforeAll, afterAll, beforeEach } from '@jest/globals';
import request from 'supertest';
import { Express } from 'express';
import { createTestServer } from '../helpers/testServer';
import { getDb } from '../../src/database';
import { users } from '../../src/database/schema';
import { eq } from 'drizzle-orm';

describe('Auth Integration Tests', () => {
  let app: Express;
  let authToken: string;

  beforeAll(async () => {
    app = await createTestServer();
  });

  beforeEach(async () => {
    // Clean up database
    const db = getDb();
    await db.delete(users);
  });

  describe('POST /api/auth/register', () => {
    it('should register a new user', async () => {
      const userData = {
        email: 'newuser@example.com',
        username: 'newuser',
        password: 'Password123!',
        firstName: 'New',
        lastName: 'User',
      };

      const response = await request(app)
        .post('/api/auth/register')
        .send(userData)
        .expect(201);

      expect(response.body).toHaveProperty('user');
      expect(response.body).toHaveProperty('token');
      expect(response.body.user.email).toBe(userData.email);
      expect(response.body.user.username).toBe(userData.username);
      expect(response.body.user).not.toHaveProperty('passwordHash');
    });

    it('should validate email format', async () => {
      const userData = {
        email: 'invalid-email',
        username: 'newuser',
        password: 'Password123!',
      };

      const response = await request(app)
        .post('/api/auth/register')
        .send(userData)
        .expect(400);

      expect(response.body).toHaveProperty('error');
      expect(response.body.error).toContain('email');
    });

    it('should require strong password', async () => {
      const userData = {
        email: 'user@example.com',
        username: 'newuser',
        password: 'weak',
      };

      const response = await request(app)
        .post('/api/auth/register')
        .send(userData)
        .expect(400);

      expect(response.body).toHaveProperty('error');
      expect(response.body.error).toContain('password');
    });

    it('should prevent duplicate email registration', async () => {
      const userData = {
        email: 'duplicate@example.com',
        username: 'user1',
        password: 'Password123!',
      };

      // First registration
      await request(app)
        .post('/api/auth/register')
        .send(userData)
        .expect(201);

      // Duplicate registration
      const response = await request(app)
        .post('/api/auth/register')
        .send({
          ...userData,
          username: 'user2', // Different username, same email
        })
        .expect(409);

      expect(response.body.error).toContain('Email already registered');
    });
  });

  describe('POST /api/auth/login', () => {
    beforeEach(async () => {
      // Create a test user
      await request(app)
        .post('/api/auth/register')
        .send({
          email: 'testuser@example.com',
          username: 'testuser',
          password: 'Password123!',
        });
    });

    it('should login with valid credentials', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({
          email: 'testuser@example.com',
          password: 'Password123!',
        })
        .expect(200);

      expect(response.body).toHaveProperty('user');
      expect(response.body).toHaveProperty('token');
      expect(response.body.user.email).toBe('testuser@example.com');
      
      authToken = response.body.token;
    });

    it('should reject invalid password', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({
          email: 'testuser@example.com',
          password: 'WrongPassword!',
        })
        .expect(401);

      expect(response.body.error).toContain('Invalid credentials');
    });

    it('should reject non-existent email', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({
          email: 'nonexistent@example.com',
          password: 'Password123!',
        })
        .expect(401);

      expect(response.body.error).toContain('Invalid credentials');
    });

    it('should support login with username', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({
          email: 'testuser', // Username instead of email
          password: 'Password123!',
        })
        .expect(200);

      expect(response.body).toHaveProperty('token');
      expect(response.body.user.username).toBe('testuser');
    });
  });

  describe('GET /api/auth/me', () => {
    beforeEach(async () => {
      const response = await request(app)
        .post('/api/auth/register')
        .send({
          email: 'authuser@example.com',
          username: 'authuser',
          password: 'Password123!',
        });
      
      authToken = response.body.token;
    });

    it('should return current user with valid token', async () => {
      const response = await request(app)
        .get('/api/auth/me')
        .set('Authorization', `Bearer ${authToken}`)
        .expect(200);

      expect(response.body).toHaveProperty('user');
      expect(response.body.user.email).toBe('authuser@example.com');
      expect(response.body.user).not.toHaveProperty('passwordHash');
    });

    it('should reject request without token', async () => {
      await request(app)
        .get('/api/auth/me')
        .expect(401);
    });

    it('should reject request with invalid token', async () => {
      await request(app)
        .get('/api/auth/me')
        .set('Authorization', 'Bearer invalid-token')
        .expect(401);
    });
  });

  describe('POST /api/auth/refresh', () => {
    it('should refresh valid token', async () => {
      const response = await request(app)
        .post('/api/auth/refresh')
        .set('Authorization', `Bearer ${authToken}`)
        .expect(200);

      expect(response.body).toHaveProperty('token');
      expect(response.body.token).not.toBe(authToken);
    });
  });

  describe('POST /api/auth/change-password', () => {
    beforeEach(async () => {
      const response = await request(app)
        .post('/api/auth/register')
        .send({
          email: 'passuser@example.com',
          username: 'passuser',
          password: 'OldPassword123!',
        });
      
      authToken = response.body.token;
    });

    it('should change password with valid old password', async () => {
      await request(app)
        .post('/api/auth/change-password')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          oldPassword: 'OldPassword123!',
          newPassword: 'NewPassword123!',
        })
        .expect(200);

      // Try logging in with new password
      const loginResponse = await request(app)
        .post('/api/auth/login')
        .send({
          email: 'passuser@example.com',
          password: 'NewPassword123!',
        })
        .expect(200);

      expect(loginResponse.body).toHaveProperty('token');
    });

    it('should reject change with wrong old password', async () => {
      const response = await request(app)
        .post('/api/auth/change-password')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          oldPassword: 'WrongOldPassword!',
          newPassword: 'NewPassword123!',
        })
        .expect(401);

      expect(response.body.error).toContain('Current password is incorrect');
    });
  });

  describe('POST /api/auth/logout', () => {
    it('should logout successfully', async () => {
      await request(app)
        .post('/api/auth/logout')
        .set('Authorization', `Bearer ${authToken}`)
        .expect(200);

      // Token should still be valid (logout is client-side in JWT)
      await request(app)
        .get('/api/auth/me')
        .set('Authorization', `Bearer ${authToken}`)
        .expect(200);
    });
  });
});