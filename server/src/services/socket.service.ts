import { Server as SocketIOServer, Socket } from 'socket.io';
import jwt from 'jsonwebtoken';
import { getDb } from '../database';
import { users, devices } from '../database/schema';
import { eq } from 'drizzle-orm';
import { logger } from '../utils/logger';
import { getRedisClient, publish, subscribe } from './redis.service';

interface AuthenticatedSocket extends Socket {
  userId?: string;
  deviceId?: string;
}

let io: SocketIOServer;

export function initializeSocketIO(socketServer: SocketIOServer) {
  io = socketServer;

  // Authentication middleware
  io.use(async (socket: AuthenticatedSocket, next) => {
    try {
      const token = socket.handshake.auth.token;
      if (!token) {
        return next(new Error('Authentication required'));
      }

      // Verify JWT
      const decoded = jwt.verify(token, process.env.JWT_SECRET!) as any;
      socket.userId = decoded.userId;
      socket.deviceId = socket.handshake.query.deviceId as string;

      // Update device last seen
      if (socket.deviceId) {
        const db = getDb();
        await db
          .update(devices)
          .set({ lastSyncAt: new Date() })
          .where(eq(devices.deviceId, socket.deviceId));
      }

      next();
    } catch (error) {
      logger.error('Socket authentication error:', error);
      next(new Error('Authentication failed'));
    }
  });

  // Connection handler
  io.on('connection', async (socket: AuthenticatedSocket) => {
    logger.info(`User ${socket.userId} connected from device ${socket.deviceId}`);

    // Join user room
    if (socket.userId) {
      socket.join(`user:${socket.userId}`);
      
      // Join device room
      if (socket.deviceId) {
        socket.join(`device:${socket.deviceId}`);
      }
    }

    // Handle real-time sync
    socket.on('sync:start', async (data) => {
      logger.info(`Sync started for user ${socket.userId}`);
      
      // Notify other devices
      socket.to(`user:${socket.userId}`).emit('sync:started', {
        deviceId: socket.deviceId,
        timestamp: new Date(),
      });
    });

    socket.on('sync:changes', async (changes) => {
      logger.info(`Sync changes from device ${socket.deviceId}:`, changes);
      
      // Broadcast changes to other devices
      socket.to(`user:${socket.userId}`).emit('sync:update', {
        deviceId: socket.deviceId,
        changes,
        timestamp: new Date(),
      });

      // Store changes in Redis for offline devices
      const redis = getRedisClient();
      const key = `sync:pending:${socket.userId}`;
      await redis.lpush(key, JSON.stringify({
        deviceId: socket.deviceId,
        changes,
        timestamp: new Date(),
      }));
      await redis.expire(key, 86400); // 24 hours
    });

    // Handle collaboration - Join/leave folder room
    socket.on('collab:join-folder', async (folderId: string) => {
      socket.join(`folder:${folderId}`);
      logger.info(`User ${socket.userId} joined folder ${folderId}`);
    });

    socket.on('collab:leave-folder', async (folderId: string) => {
      socket.leave(`folder:${folderId}`);
      logger.info(`User ${socket.userId} left folder ${folderId}`);
    });

    // Handle collaboration sessions
    socket.on('collab:join-session', async (sessionId: string) => {
      socket.join(`session:${sessionId}`);
      
      // Notify others in the session
      socket.to(`session:${sessionId}`).emit('collab:user-joined-session', {
        userId: socket.userId,
        timestamp: new Date(),
      });
    });

    socket.on('collab:leave-session', async (sessionId: string) => {
      socket.leave(`session:${sessionId}`);
      
      // Notify others in the session
      socket.to(`session:${sessionId}`).emit('collab:user-left-session', {
        userId: socket.userId,
        timestamp: new Date(),
      });
    });

    // Handle real-time annotations
    socket.on('collab:annotation', async (data) => {
      // Broadcast annotation to session participants
      socket.to(`session:${data.sessionId}`).emit('collab:annotation-update', {
        userId: socket.userId,
        ...data,
      });
    });

    // Handle cursor tracking
    socket.on('collab:cursor', async (data) => {
      // Broadcast cursor position to folder members
      socket.to(`folder:${data.folderId}`).emit('collab:cursor-update', {
        userId: socket.userId,
        ...data,
      });
    });

    // Handle live typing indicators
    socket.on('collab:typing', async (data) => {
      // Broadcast typing status
      socket.to(`session:${data.sessionId}`).emit('collab:typing-update', {
        userId: socket.userId,
        isTyping: data.isTyping,
        timestamp: new Date(),
      });
    });

    // Handle article interactions
    socket.on('article:read', async (articleId: string) => {
      // Broadcast to other devices
      socket.to(`user:${socket.userId}`).emit('article:marked-read', {
        articleId,
        deviceId: socket.deviceId,
      });
    });

    socket.on('article:star', async (articleId: string) => {
      // Broadcast to other devices
      socket.to(`user:${socket.userId}`).emit('article:starred', {
        articleId,
        deviceId: socket.deviceId,
      });
    });

    // Handle live feed updates
    socket.on('feed:subscribe', async (feedId: string) => {
      socket.join(`feed:${feedId}`);
    });

    socket.on('feed:unsubscribe', async (feedId: string) => {
      socket.leave(`feed:${feedId}`);
    });

    // Handle disconnection
    socket.on('disconnect', () => {
      logger.info(`User ${socket.userId} disconnected from device ${socket.deviceId}`);
    });
  });

  // Subscribe to Redis pub/sub for cross-server communication
  subscribe('feed:new-articles', (data) => {
    // Notify all users subscribed to this feed
    io.to(`feed:${data.feedId}`).emit('feed:new-articles', data);
  });

  subscribe('user:notification', (data) => {
    // Send notification to specific user
    io.to(`user:${data.userId}`).emit('notification', data);
  });

  // Initialize market WebSocket namespace
  const { initializeMarketWebSocket } = require('./market/websocket');
  initializeMarketWebSocket(io);

  return io;
}

export function getIO(): SocketIOServer {
  if (!io) {
    throw new Error('Socket.IO not initialized');
  }
  return io;
}

// Utility functions for emitting events
export function emitToUser(userId: string, event: string, data: any) {
  io.to(`user:${userId}`).emit(event, data);
}

export function emitToDevice(deviceId: string, event: string, data: any) {
  io.to(`device:${deviceId}`).emit(event, data);
}

export function emitToFolder(folderId: string, event: string, data: any) {
  io.to(`folder:${folderId}`).emit(event, data);
}

export function emitToFeed(feedId: string, event: string, data: any) {
  io.to(`feed:${feedId}`).emit(event, data);
}

export async function broadcastFeedUpdate(feedId: string, articles: any[]) {
  // Emit via Socket.IO
  emitToFeed(feedId, 'feed:new-articles', {
    feedId,
    articles,
    timestamp: new Date(),
  });

  // Publish to Redis for other servers
  await publish('feed:new-articles', {
    feedId,
    articles,
    timestamp: new Date(),
  });
}

export async function sendNotificationToUser(userId: string, notification: any) {
  // Emit via Socket.IO
  emitToUser(userId, 'notification', notification);

  // Publish to Redis for other servers
  await publish('user:notification', {
    userId,
    ...notification,
  });
}