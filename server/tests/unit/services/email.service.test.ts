import { describe, it, expect, afterAll, jest } from '@jest/globals';
import nodemailer from 'nodemailer';
import {
  initializeEmailService,
  isEmailConfigured,
  sendEmail,
} from '../../../src/services/email.service';

jest.unmock('../../../src/services/email.service');
jest.mock('nodemailer', () => ({
  __esModule: true,
  default: {
    createTransport: jest.fn(),
  },
}));

describe('email service', () => {
  afterAll(() => {
    delete process.env.SMTP_HOST;
  });

  describe('initializeEmailService', () => {
    it('should be a graceful no-op when SMTP is not configured', async () => {
      delete process.env.SMTP_HOST;

      await expect(initializeEmailService()).resolves.toBeUndefined();
      expect(isEmailConfigured()).toBe(false);
      expect(nodemailer.createTransport).not.toHaveBeenCalled();
    });

    it('should stay disabled when transporter verification fails', async () => {
      process.env.SMTP_HOST = 'smtp.example.com';
      (nodemailer.createTransport as jest.Mock).mockReturnValue({
        verify: jest.fn<() => Promise<unknown>>().mockRejectedValue(new Error('connect ECONNREFUSED')),
      });

      await expect(initializeEmailService()).resolves.toBeUndefined();
      expect(isEmailConfigured()).toBe(false);
    });

    it('should be configured after successful verification', async () => {
      process.env.SMTP_HOST = 'smtp.example.com';
      (nodemailer.createTransport as jest.Mock).mockReturnValue({
        verify: jest.fn<() => Promise<unknown>>().mockResolvedValue(true),
      });

      await initializeEmailService();
      expect(isEmailConfigured()).toBe(true);
    });
  });

  describe('sendEmail', () => {
    it('should skip (return false) instead of throwing when SMTP is not configured', async () => {
      delete process.env.SMTP_HOST;
      await initializeEmailService();

      await expect(
        sendEmail({
          to: 'user@example.com',
          subject: 'Verify your Omi RSS account',
          template: 'email-verification',
          data: { username: 'user', verificationUrl: 'http://localhost:3001/verify-email?token=abc' },
        }),
      ).resolves.toBe(false);
    });
  });
});
