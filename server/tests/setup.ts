import dotenv from 'dotenv';
import { jest } from '@jest/globals';

// Load test environment variables
dotenv.config({ path: '.env.test' });

// Set test environment
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-secret-key';
process.env.DATABASE_URL = 'postgresql://test:test@localhost:5432/omi_rss_test';
process.env.REDIS_URL = 'redis://localhost:6379/1';

// Mock external services
jest.mock('../src/services/email.service');
jest.mock('../src/services/push');
jest.mock('../src/workers');

// Global test utilities
global.testUtils = {
  generateId: () => Math.random().toString(36).substring(2, 15),
  
  createTestUser: (overrides = {}) => ({
    id: global.testUtils.generateId(),
    email: 'test@example.com',
    username: 'testuser',
    passwordHash: '$2b$10$YourHashedPasswordHere',
    role: 'user',
    isActive: true,
    emailVerified: true,
    createdAt: new Date(),
    updatedAt: new Date(),
    ...overrides,
  }),
  
  createTestFeed: (userId: string, overrides = {}) => ({
    id: global.testUtils.generateId(),
    userId,
    url: 'https://example.com/feed.xml',
    title: 'Test Feed',
    description: 'A test RSS feed',
    siteUrl: 'https://example.com',
    isActive: true,
    createdAt: new Date(),
    updatedAt: new Date(),
    ...overrides,
  }),
  
  createTestArticle: (feedId: string, overrides = {}) => ({
    id: global.testUtils.generateId(),
    feedId,
    guid: `article-${Date.now()}`,
    url: 'https://example.com/article',
    title: 'Test Article',
    content: 'Test article content',
    author: 'Test Author',
    publishedAt: new Date(),
    createdAt: new Date(),
    updatedAt: new Date(),
    ...overrides,
  }),
  
  sleep: (ms: number) => new Promise(resolve => setTimeout(resolve, ms)),
};

// Extend Jest matchers
expect.extend({
  toBeWithinRange(received: number, floor: number, ceiling: number) {
    const pass = received >= floor && received <= ceiling;
    if (pass) {
      return {
        message: () => `expected ${received} not to be within range ${floor} - ${ceiling}`,
        pass: true,
      };
    } else {
      return {
        message: () => `expected ${received} to be within range ${floor} - ${ceiling}`,
        pass: false,
      };
    }
  },
  
  toBeValidDate(received: any) {
    const pass = received instanceof Date && !isNaN(received.getTime());
    if (pass) {
      return {
        message: () => `expected ${received} not to be a valid date`,
        pass: true,
      };
    } else {
      return {
        message: () => `expected ${received} to be a valid date`,
        pass: false,
      };
    }
  },
});

// Clean up after tests
afterAll(async () => {
  // Close database connections
  const { closeDatabase } = await import('../src/database');
  await closeDatabase();
  
  // Close Redis connections
  const { closeRedis } = await import('../src/services/redis.service');
  await closeRedis();
  
  // Close workers
  const { closeWorkers } = await import('../src/workers');
  await closeWorkers();
});

// Suppress console logs in tests unless DEBUG is set
if (!process.env.DEBUG) {
  global.console = {
    ...console,
    log: jest.fn(),
    debug: jest.fn(),
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  };
}

// TypeScript declarations
declare global {
  namespace NodeJS {
    interface Global {
      testUtils: {
        generateId: () => string;
        createTestUser: (overrides?: any) => any;
        createTestFeed: (userId: string, overrides?: any) => any;
        createTestArticle: (feedId: string, overrides?: any) => any;
        sleep: (ms: number) => Promise<void>;
      };
    }
  }
  
  namespace jest {
    interface Matchers<R> {
      toBeWithinRange(floor: number, ceiling: number): R;
      toBeValidDate(): R;
    }
  }
}