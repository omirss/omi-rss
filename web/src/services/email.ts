// Ported from server/src/services/email.service.ts (v0.2.1): same init/skip
// semantics, same template rendering (handlebars over src/templates/*.hbs),
// never throws.

import nodemailer from "nodemailer";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import handlebars from "handlebars";

interface EmailOptions {
  to: string | string[];
  subject: string;
  template?: string;
  html?: string;
  text?: string;
  data?: Record<string, unknown>;
  attachments?: unknown[];
}

let transporter: ReturnType<typeof nodemailer.createTransport> | undefined;

export function isEmailConfigured(): boolean {
  return transporter !== undefined;
}

// Initialize email transporter. No-op (with warning) when SMTP is not
// configured so self-hosted instances without SMTP still boot, register
// and log in fine.
export async function initializeEmailService(): Promise<void> {
  if (!process.env.SMTP_HOST) {
    transporter = undefined;
    console.warn(
      "SMTP_HOST not set, email delivery disabled (verification and password reset emails will be skipped)"
    );
    return;
  }

  try {
    transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: parseInt(process.env.SMTP_PORT || "587"),
      secure: process.env.SMTP_PORT === "465",
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    });

    await transporter.verify();
    console.info("Email service initialized successfully");
  } catch (error) {
    transporter = undefined;
    console.error("Failed to initialize email service:", error);
  }
}

// The Express service resolved templates relative to __dirname; the bundled
// Neutron runtime has no stable __dirname, so try the module-relative path
// first (dev + unbundled prod) and fall back to cwd-relative layouts.
function templateCandidates(name: string): string[] {
  const moduleRelative = path.join(
    path.dirname(fileURLToPath(import.meta.url)),
    "..",
    "templates",
    `${name}.hbs`
  );
  return [moduleRelative, path.join(process.cwd(), "src", "templates", `${name}.hbs`)];
}

async function readTemplate(name: string): Promise<string> {
  const candidates = templateCandidates(name);
  let lastError: unknown = new Error(`Template not found: ${name}`);
  for (const candidate of candidates) {
    try {
      return await fs.readFile(candidate, "utf-8");
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

// Returns true when the email was delivered, false when it was skipped
// (SMTP not configured) or the delivery failed. Never throws.
export async function sendEmail(options: EmailOptions): Promise<boolean> {
  try {
    if (!transporter) {
      console.warn("Email service not initialized, skipping email send");
      return false;
    }

    let { html } = options;
    const { text } = options;

    if (options.template) {
      const templateContent = await readTemplate(options.template);
      const template = handlebars.compile(templateContent);
      html = template(options.data || {});
    }

    const info = await transporter.sendMail({
      from: process.env.EMAIL_FROM || "Omi RSS <noreply@omirss.com>",
      to: Array.isArray(options.to) ? options.to.join(", ") : options.to,
      subject: options.subject,
      html,
      text: text || html?.replace(/<[^>]*>/g, ""),
      attachments: options.attachments as never,
    });

    console.info(`Email sent: ${info.messageId}`);
    return true;
  } catch (error) {
    console.error("Failed to send email:", error);
    return false;
  }
}
