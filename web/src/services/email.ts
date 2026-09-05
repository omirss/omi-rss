// Ported from server/src/services/email.service.ts — interface preserved for
// the email wave. Delivery is a log-and-return-false no-op until then.

interface EmailOptions {
  to: string | string[];
  subject: string;
  template?: string;
  html?: string;
  text?: string;
  data?: Record<string, unknown>;
  attachments?: unknown[];
}

let initialized = false;

export function isEmailConfigured(): boolean {
  return initialized;
}

// Idempotent. No-op (with warning) when SMTP is not configured so instances
// without SMTP still boot, register and log in fine.
export async function initializeEmailService(): Promise<void> {
  if (!process.env.SMTP_HOST) {
    console.warn(
      "SMTP_HOST not set, email delivery disabled (verification and password reset emails will be skipped)"
    );
    initialized = true;
    return;
  }
  console.warn("omi-rss-web email delivery not ported yet; SMTP configuration ignored");
  initialized = true;
}

async function ensureInitialized(): Promise<void> {
  if (!initialized) {
    await initializeEmailService();
  }
}

// Returns true when the email was delivered, false when it was skipped
// (SMTP not configured) or the delivery failed. Never throws.
export async function sendEmail(options: EmailOptions): Promise<boolean> {
  await ensureInitialized();
  console.warn(
    `omi-rss-web email stub: skipped send to=${Array.isArray(options.to) ? options.to.join(", ") : options.to} subject="${options.subject}" template=${options.template ?? "-"}`
  );
  return false;
}
