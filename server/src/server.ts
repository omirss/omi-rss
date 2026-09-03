import express, { Express, Request, Response, NextFunction } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import morgan from 'morgan';
import { createServer } from 'http';
import { Server as SocketIOServer } from 'socket.io';
import dotenv from 'dotenv';
import path from 'path';

// Load environment variables
dotenv.config();

// Import middleware
import { errorHandler } from './middleware/errorHandler';
import { rateLimiter } from './middleware/rateLimiter';
import { authentication } from './middleware/authentication';
import { logger } from './utils/logger';

// Import routers
import authRouter from './routes/auth.routes';
import userRouter from './routes/user.routes';
import feedRouter from './routes/feed.routes';
import articleRouter from './routes/article.routes';
import folderRouter from './routes/folder.routes';
import syncRouter from './routes/sync.routes';
import statsRouter from './routes/stats.routes';
import aiRouter from './routes/ai.routes';
import marketRouter from './routes/market.routes';
import notificationRouter from './routes/notification.routes';
import teamRouter from './routes/team.routes';
import collaborationRouter from './routes/collaboration';
import discoveryRouter from './routes/discovery';
import pushRouter from './routes/push.routes';
import contentRouter from './routes/content.routes';
import analyticsRouter from './routes/analytics';
import paywallRouter from './routes/paywall';
import searchRouter from './routes/search';

// Import services
import { initializeDatabase } from './database/index';
import { initializeRedis } from './services/redis.service';
import { initializeSocketIO } from './services/socket.service';
import { initializeCollaboration } from './services/collaboration';
import { initializeWorkers } from './workers/index';

class Server {
  private app: Express;
  private httpServer: any;
  private io: SocketIOServer;
  private port: number;

  constructor() {
    this.app = express();
    this.httpServer = createServer(this.app);
    this.io = new SocketIOServer(this.httpServer, {
      cors: {
        origin: process.env.CORS_ORIGIN?.split(',') || ['http://localhost:3001'],
        credentials: true
      }
    });
    this.port = parseInt(process.env.PORT || '3000', 10);
  }

  private async initializeServices(): Promise<void> {
    try {
      // Initialize database
      await initializeDatabase();
      logger.info('Database initialized successfully');

      // Initialize Redis
      await initializeRedis();
      logger.info('Redis initialized successfully');

      // Initialize Socket.IO
      initializeSocketIO(this.io);
      logger.info('Socket.IO initialized successfully');

      // Initialize collaboration service
      initializeCollaboration(this.io);
      logger.info('Collaboration service initialized successfully');

      // Initialize background workers
      await initializeWorkers();
      logger.info('Background workers initialized successfully');
    } catch (error) {
      logger.error('Failed to initialize services:', error);
      process.exit(1);
    }
  }

  private setupMiddleware(): void {
    // Security middleware
    this.app.use(helmet({
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          styleSrc: ["'self'", "'unsafe-inline'"],
          scriptSrc: ["'self'"],
          imgSrc: ["'self'", "data:", "https:"],
        },
      },
    }));

    // CORS configuration
    this.app.use(cors({
      origin: process.env.CORS_ORIGIN?.split(',') || ['http://localhost:3001'],
      credentials: true,
      optionsSuccessStatus: 200
    }));

    // Compression
    this.app.use(compression());

    // Body parsing
    this.app.use(express.json({ limit: '10mb' }));
    this.app.use(express.urlencoded({ extended: true, limit: '10mb' }));

    // Logging
    this.app.use(morgan('combined', {
      stream: {
        write: (message: string) => logger.info(message.trim())
      }
    }));

    // Static files
    this.app.use('/uploads', express.static(path.join(__dirname, '../uploads')));

    // Rate limiting
    this.app.use('/api/', rateLimiter);

    // Request ID
    this.app.use((req: Request, res: Response, next: NextFunction) => {
      req.id = `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
      res.setHeader('X-Request-ID', req.id);
      next();
    });
  }

  private setupRoutes(): void {
    // Health check
    this.app.get('/health', (req: Request, res: Response) => {
      res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        environment: process.env.NODE_ENV,
        version: process.env.npm_package_version || '1.0.0'
      });
    });

    // API Routes
    this.app.use('/api/auth', authRouter);
    this.app.use('/api/users', authentication, userRouter);
    this.app.use('/api/feeds', authentication, feedRouter);
    this.app.use('/api/articles', authentication, articleRouter);
    this.app.use('/api/folders', authentication, folderRouter);
    this.app.use('/api/sync', authentication, syncRouter);
    this.app.use('/api/stats', authentication, statsRouter);
    this.app.use('/api/ai', authentication, aiRouter);
    this.app.use('/api/market', authentication, marketRouter);
    this.app.use('/api/notifications', authentication, notificationRouter);
    this.app.use('/api/teams', authentication, teamRouter);
    this.app.use('/api/collaboration', authentication, collaborationRouter);
    this.app.use('/api/discovery', authentication, discoveryRouter);
    this.app.use('/api/push', authentication, pushRouter);
    this.app.use('/api/content', authentication, contentRouter);
    this.app.use('/api/analytics', authentication, analyticsRouter);
    this.app.use('/api/paywall', authentication, paywallRouter);
    this.app.use('/api/search', authentication, searchRouter);

    // 404 handler
    this.app.use((req: Request, res: Response) => {
      res.status(404).json({
        error: 'Not Found',
        message: `Cannot ${req.method} ${req.path}`,
        timestamp: new Date().toISOString()
      });
    });

    // Error handling middleware (must be last)
    this.app.use(errorHandler);
  }

  private setupGracefulShutdown(): void {
    const shutdown = async (signal: string) => {
      logger.info(`${signal} received, shutting down gracefully...`);
      
      // Stop accepting new connections
      this.httpServer.close(() => {
        logger.info('HTTP server closed');
      });

      // Close Socket.IO connections
      this.io.close(() => {
        logger.info('Socket.IO server closed');
      });

      // Close database connections
      // await closeDatabase();
      
      // Close Redis connections
      // await closeRedis();

      // Exit process
      process.exit(0);
    };

    // Listen for termination signals
    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));

    // Handle uncaught exceptions
    process.on('uncaughtException', (error: Error) => {
      logger.error('Uncaught Exception:', error);
      shutdown('uncaughtException');
    });

    // Handle unhandled promise rejections
    process.on('unhandledRejection', (reason: any, promise: Promise<any>) => {
      logger.error('Unhandled Rejection at:', promise, 'reason:', reason);
      shutdown('unhandledRejection');
    });
  }

  public async start(): Promise<void> {
    try {
      // Initialize services
      await this.initializeServices();

      // Setup middleware
      this.setupMiddleware();

      // Setup routes
      this.setupRoutes();

      // Setup graceful shutdown
      this.setupGracefulShutdown();

      // Start server
      this.httpServer.listen(this.port, () => {
        logger.info(`
🚀 Omi RSS Server is running!
📍 Environment: ${process.env.NODE_ENV}
🌐 Server: http://localhost:${this.port}
🔌 WebSocket: ws://localhost:${this.port}
📊 Health: http://localhost:${this.port}/health
📚 API Docs: http://localhost:${this.port}/api-docs
        `);
      });
    } catch (error) {
      logger.error('Failed to start server:', error);
      process.exit(1);
    }
  }
}

// Create and start server
const server = new Server();
server.start().catch((error) => {
  logger.error('Server startup failed:', error);
  process.exit(1);
});

// Extend Express Request type
declare global {
  namespace Express {
    interface Request {
      id?: string;
      user?: {
        id: string;
        email: string;
        username: string;
        role: string;
      };
    }
  }
}

export default server;