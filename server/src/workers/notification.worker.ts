import Queue from 'bull';
import { pushService } from '../services/push';
import { logger } from '../utils/logger';
import { getDb } from '../database';
import { notifications } from '../database/schema';
import { eq } from 'drizzle-orm';

export function notificationWorker(queue: Queue.Queue) {
  queue.process('send-push', async (job) => {
    const { userId, userIds, topic, notification } = job.data;

    try {
      logger.info(`Processing push notification job ${job.id}`);

      // Initialize push service if needed
      await pushService.initialize();

      let result;

      if (userId) {
        // Send to single user
        result = await pushService.sendToUser(userId, notification);
      } else if (userIds) {
        // Send to multiple users
        result = await pushService.sendToUsers(userIds, notification);
      } else if (topic) {
        // Send to topic
        result = await pushService.sendToTopic(topic, notification);
      } else {
        throw new Error('No recipient specified');
      }

      logger.info(`Push notification sent: ${result.sent} success, ${result.failed} failed`);
      return result;
    } catch (error) {
      logger.error('Push notification job failed:', error);
      throw error;
    }
  });

  queue.process('send-email', async (job) => {
    const { userId, email, subject, body, template, data } = job.data;

    try {
      logger.info(`Processing email job ${job.id}`);

      // TODO: Implement email sending
      // For now, just log and save to database
      const db = getDb();

      await db
        .insert(notifications)
        .values({
          userId,
          type: 'email',
          title: subject,
          body: body || 'Email notification',
          data: { email, template, ...data },
          channels: ['email'],
          status: 'sent',
          sentAt: new Date(),
        });

      logger.info(`Email queued for ${email}: ${subject}`);
      return { success: true };
    } catch (error) {
      logger.error('Email job failed:', error);
      throw error;
    }
  });

  queue.process('send-sms', async (job) => {
    const { userId, phone, message } = job.data;

    try {
      logger.info(`Processing SMS job ${job.id}`);

      // TODO: Implement SMS sending (Twilio, etc.)
      // For now, just log
      logger.info(`SMS queued for ${phone}: ${message}`);
      return { success: true };
    } catch (error) {
      logger.error('SMS job failed:', error);
      throw error;
    }
  });

  queue.process('mark-read', async (job) => {
    const { notificationId, userId } = job.data;

    try {
      const db = getDb();

      await db
        .update(notifications)
        .set({ readAt: new Date() })
        .where(
          eq(notifications.id, notificationId),
          eq(notifications.userId, userId)
        );

      return { success: true };
    } catch (error) {
      logger.error('Mark read job failed:', error);
      throw error;
    }
  });

  // Error handling
  queue.on('failed', (job, err) => {
    logger.error(`Notification job ${job.id} failed:`, err);
  });

  queue.on('completed', (job) => {
    logger.info(`Notification job ${job.id} completed`);
  });

  logger.info('Notification worker initialized');
}