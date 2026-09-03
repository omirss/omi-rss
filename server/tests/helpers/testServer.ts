import express, { Express } from 'express';
import { errorHandler } from '../../src/middleware/errorHandler';
import authRouter from '../../src/routes/auth.routes';
import userRouter from '../../src/routes/user.routes';
import feedRouter from '../../src/routes/feed.routes';
import articleRouter from '../../src/routes/article.routes';
import { authentication } from '../../src/middleware/authentication';
import { initializeDatabase } from '../../src/database';
import { initializeRedis } from '../../src/services/redis.service';

let testApp: Express | null = null;

export async function createTestServer(): Promise<Express> {
  if (testApp) return testApp;

  // Initialize services
  await initializeDatabase();
  await initializeRedis();

  const app = express();

  // Middleware
  app.use(express.json());
  app.use(express.urlencoded({ extended: true }));

  // Routes
  app.use('/api/auth', authRouter);
  app.use('/api/users', authentication, userRouter);
  app.use('/api/feeds', authentication, feedRouter);
  app.use('/api/articles', authentication, articleRouter);

  // Error handling
  app.use(errorHandler);

  testApp = app;
  return app;
}

export async function closeTestServer(): Promise<void> {
  // Cleanup is handled in test setup
  testApp = null;
}