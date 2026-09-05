import { z } from "zod";
import crypto from "node:crypto";
import { eq } from "drizzle-orm";
import { users } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { handle, jsonResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { authRateLimitKey, consumeAuthRateLimit } from "../../../lib/api/rate-limit.js";
import { sendEmail } from "../../../services/email.js";

export const config = { mode: "app" };

const forgotPasswordSchema = z.object({
  email: z.string().email(),
});

export async function action({ request }: { request: Request }) {
  return handle(async () => {
    await consumeAuthRateLimit(authRateLimitKey(request));

    const data = forgotPasswordSchema.parse(await readJsonBody(request));

    const db = await getDb();

    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.email, data.email))
      .limit(1);

    if (!user) {
      return jsonResponse({ message: "If an account exists, a password reset email has been sent." });
    }

    const resetToken = crypto.randomBytes(32).toString("hex");
    const resetExpires = new Date(Date.now() + 3600000);

    await db
      .update(users)
      .set({
        passwordResetToken: resetToken,
        passwordResetExpires: resetExpires,
      })
      .where(eq(users.id, user.id));

    await sendEmail({
      to: user.email,
      subject: "Reset your Omi RSS password",
      template: "password-reset",
      data: {
        username: user.username,
        resetUrl: `${process.env.FRONTEND_URL}/reset-password?token=${resetToken}`,
      },
    });

    console.info(`Password reset requested for: ${user.email}`);

    return jsonResponse({ message: "If an account exists, a password reset email has been sent." });
  });
}
