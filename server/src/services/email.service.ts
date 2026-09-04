import nodemailer from 'nodemailer';
import { logger } from '../utils/logger';
import fs from 'fs/promises';
import path from 'path';
import handlebars from 'handlebars';

let transporter: nodemailer.Transporter | undefined;

export function isEmailConfigured(): boolean {
  return transporter !== undefined;
}

// Initialize email transporter. No-op (with warning) when SMTP is not
// configured so self-hosted instances without SMTP still boot, register
// and log in fine.
export async function initializeEmailService() {
  if (!process.env.SMTP_HOST) {
    transporter = undefined;
    logger.warn('SMTP_HOST not set, email delivery disabled (verification and password reset emails will be skipped)');
    return;
  }

  try {
    transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: parseInt(process.env.SMTP_PORT || '587'),
      secure: process.env.SMTP_PORT === '465',
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    });

    await transporter.verify();
    logger.info('Email service initialized successfully');
  } catch (error) {
    transporter = undefined;
    logger.error('Failed to initialize email service:', error);
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

// Returns true when the email was delivered, false when it was skipped
// (SMTP not configured) or the delivery failed. Never throws.
export async function sendEmail(options: EmailOptions): Promise<boolean> {
  try {
    if (!transporter) {
      logger.warn('Email service not initialized, skipping email send');
      return false;
    }

    let { html } = options;
    const { text } = options;

    if (options.template) {
      const templatePath = path.join(__dirname, `../templates/${options.template}.hbs`);
      const templateContent = await fs.readFile(templatePath, 'utf-8');
      const template = handlebars.compile(templateContent);
      html = template(options.data || {});
    }

    const info = await transporter.sendMail({
      from: process.env.EMAIL_FROM || 'Omi RSS <noreply@omirss.com>',
      to: Array.isArray(options.to) ? options.to.join(', ') : options.to,
      subject: options.subject,
      html,
      text: text || html?.replace(/<[^>]*>/g, ''),
      attachments: options.attachments,
    });

    logger.info(`Email sent: ${info.messageId}`);
    return true;
  } catch (error) {
    logger.error('Failed to send email:', error);
    return false;
  }
}
