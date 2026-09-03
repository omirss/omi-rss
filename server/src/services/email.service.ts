import nodemailer from 'nodemailer';
import { logger } from '../utils/logger';
import fs from 'fs/promises';
import path from 'path';
import handlebars from 'handlebars';

let transporter: nodemailer.Transporter;

// Initialize email transporter
export async function initializeEmailService() {
  try {
    transporter = nodemailer.createTransporter({
      host: process.env.SMTP_HOST,
      port: parseInt(process.env.SMTP_PORT || '587'),
      secure: process.env.SMTP_PORT === '465',
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    });

    // Verify connection
    await transporter.verify();
    logger.info('Email service initialized successfully');
  } catch (error) {
    logger.error('Failed to initialize email service:', error);
    // Don't throw - email service is not critical for startup
  }
}

interface EmailOptions {
  to: string | string[];
  subject: string;
  template?: string;
  html?: string;
  text?: string;
  data?: Record<string, any>;
  attachments?: any[];
}

export async function sendEmail(options: EmailOptions): Promise<void> {
  try {
    if (!transporter) {
      logger.warn('Email service not initialized, skipping email send');
      return;
    }

    let html = options.html;
    let text = options.text;

    // Load and compile template if specified
    if (options.template) {
      const templatePath = path.join(__dirname, `../templates/${options.template}.hbs`);
      const templateContent = await fs.readFile(templatePath, 'utf-8');
      const template = handlebars.compile(templateContent);
      html = template(options.data || {});
    }

    // Send email
    const info = await transporter.sendMail({
      from: process.env.EMAIL_FROM || 'Omi RSS <noreply@omirss.com>',
      to: Array.isArray(options.to) ? options.to.join(', ') : options.to,
      subject: options.subject,
      html,
      text: text || html?.replace(/<[^>]*>/g, ''), // Strip HTML for text version
      attachments: options.attachments,
    });

    logger.info(`Email sent: ${info.messageId}`);
  } catch (error) {
    logger.error('Failed to send email:', error);
    throw error;
  }
}

// Email templates
export async function sendWelcomeEmail(email: string, username: string) {
  await sendEmail({
    to: email,
    subject: 'Welcome to Omi RSS!',
    template: 'welcome',
    data: { username },
  });
}

export async function sendPasswordResetEmail(email: string, username: string, resetUrl: string) {
  await sendEmail({
    to: email,
    subject: 'Reset your Omi RSS password',
    template: 'password-reset',
    data: { username, resetUrl },
  });
}

export async function sendEmailVerificationEmail(email: string, username: string, verificationUrl: string) {
  await sendEmail({
    to: email,
    subject: 'Verify your Omi RSS email',
    template: 'email-verification',
    data: { username, verificationUrl },
  });
}

export async function sendNewArticlesNotification(email: string, articles: any[]) {
  await sendEmail({
    to: email,
    subject: `${articles.length} new articles in your RSS feeds`,
    template: 'new-articles',
    data: { articles },
  });
}

export async function sendShareInvitation(email: string, sharedBy: string, folderName: string, acceptUrl: string) {
  await sendEmail({
    to: email,
    subject: `${sharedBy} shared "${folderName}" with you`,
    template: 'share-invitation',
    data: { sharedBy, folderName, acceptUrl },
  });
}