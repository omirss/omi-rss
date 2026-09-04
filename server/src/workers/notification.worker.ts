import type Queue from 'bull';
import { logger } from '../utils/logger';
import { getDb } from '../database';
import { notifications } from '../database/schema';
import { and, eq } from 'drizzle-orm';
import { isEmailConfigured, sendEmail } from '../services/email.service';

export function notificationWorker(queue: Queue.Queue) {
  void queue.process('send-email', async (job) => {
    const { userId, email, subject, body, template, data } = job.data;

    try {
      logger.info(`Processing email job ${job.id}`);

      const db = getDb();

      if (!isEmailConfigured()) {
        await db
          .insert(notifications)
          .values({
            userId,
            type: 'email',
            title: subject,
            body: body || 'Email notification',
            data: { email, template, ...data },
            channels: ['email'],
            status: 'skipped',
          });

        logger.warn(`Email skipped (SMTP not configured) for ${email}: ${subject}`);
        return { success: true, status: 'skipped' };
      }

      const sent = await sendEmail({
        to: email,
        subject,
        text: body,
        template,
        data,
      });

      if (!sent) {
        await db
          .insert(notifications)
          .values({
            userId,
            type: 'email',
            title: subject,
            body: body || 'Email notification',
            data: { email, template, ...data },
            channels: ['email'],
            status: 'failed',
            failedAt: new Date(),
          });

        logger.error(`Email delivery failed for ${email}: ${subject}`);
        return { success: false, status: 'failed' };
      }

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

      logger.info(`Email sent to ${email}: ${subject}`);
      return { success: true, status: 'sent' };
    } catch (error) {
      logger.error('Email job failed:', error);
      throw error;
    }
  });

  void queue.process('mark-read', async (job) => {
    const { notificationId, userId } = job.data;

    try {
      const db = getDb();

      await db
        .update(notifications)
        .set({ readAt: new Date() })
        .where(
          and(
            eq(notifications.id, notificationId),
            eq(notifications.userId, userId),
          ),
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
