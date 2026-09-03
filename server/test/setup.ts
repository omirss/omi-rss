import { config } from 'dotenv';
import { jest } from '@jest/globals';

// Load test environment variables
config({ path: '.env.test' });

// Global test configuration
jest.setTimeout(30000);

// Mock Redis
jest.mock('../src/services/redis', () => ({
  getRedis: jest.fn(() => ({
    get: jest.fn(),
    set: jest.fn(),
    del: jest.fn(),
    incr: jest.fn(() => Promise.resolve(1)),
    expire: jest.fn(),
    hincrby: jest.fn(),
    hincrbyfloat: jest.fn(),
    hgetall: jest.fn(() => Promise.resolve({})),
  })),
}));

// Mock logger
jest.mock('../src/utils/logger', () => ({
  logger: {
    info: jest.fn(),
    error: jest.fn(),
    warn: jest.fn(),
    debug: jest.fn(),
  },
}));

// Mock database
jest.mock('../src/database', () => ({
  getDb: jest.fn(() => ({
    select: jest.fn().mockReturnThis(),
    from: jest.fn().mockReturnThis(),
    where: jest.fn().mockReturnThis(),
    limit: jest.fn(() => Promise.resolve([{
      id: 'test-article-id',
      title: 'Test Article',
      description: 'Test Description',
      content: 'Test Content',
    }])),
  })),
}));

// Setup global test utilities
declare global {
  var testUtils: {
    mockArticle: {
      id: string;
      title: string;
      description: string;
      content: string;
    };
    mockUser: {
      id: string;
      email: string;
      role: string;
    };
  };
}

global.testUtils = {
  mockArticle: {
    id: 'test-article-id',
    title: 'Test Article',
    description: 'Test Description',
    content: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.',
  },
  mockUser: {
    id: 'test-user-id',
    email: 'test@example.com',
    role: 'user',
  },
};