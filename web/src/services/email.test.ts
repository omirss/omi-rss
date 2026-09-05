import { describe, it, expect, vi, afterEach } from "vitest";
import nodemailer from "nodemailer";
import {
  initializeEmailService,
  isEmailConfigured,
  sendEmail,
} from "./email.js";

// Ported from server/tests/unit/services/email.service.test.ts — the skip
// paths that keep SMTP-less instances booting and registering.

vi.mock("nodemailer", () => ({
  default: {
    createTransport: vi.fn(),
  },
}));

afterEach(() => {
  delete process.env.SMTP_HOST;
  vi.clearAllMocks();
});

describe("email service", () => {
  describe("initializeEmailService", () => {
    it("should be a graceful no-op when SMTP is not configured", async () => {
      delete process.env.SMTP_HOST;

      await expect(initializeEmailService()).resolves.toBeUndefined();
      expect(isEmailConfigured()).toBe(false);
      expect(nodemailer.createTransport).not.toHaveBeenCalled();
    });

    it("should stay disabled when transporter verification fails", async () => {
      process.env.SMTP_HOST = "smtp.example.com";
      vi.mocked(nodemailer.createTransport).mockReturnValue({
        verify: vi.fn().mockRejectedValue(new Error("connect ECONNREFUSED")),
      } as never);

      await expect(initializeEmailService()).resolves.toBeUndefined();
      expect(isEmailConfigured()).toBe(false);
    });

    it("should be configured after successful verification", async () => {
      process.env.SMTP_HOST = "smtp.example.com";
      vi.mocked(nodemailer.createTransport).mockReturnValue({
        verify: vi.fn().mockResolvedValue(true),
      } as never);

      await initializeEmailService();
      expect(isEmailConfigured()).toBe(true);
    });
  });

  describe("sendEmail", () => {
    it("should skip (return false) instead of throwing when SMTP is not configured", async () => {
      delete process.env.SMTP_HOST;
      await initializeEmailService();

      await expect(
        sendEmail({
          to: "user@example.com",
          subject: "Verify your Omi RSS account",
          template: "email-verification",
          data: { username: "user", verificationUrl: "http://localhost:3001/verify-email?token=abc" },
        }),
      ).resolves.toBe(false);
    });
  });
});
