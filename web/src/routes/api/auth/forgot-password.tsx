import { z } from "zod";
import crypto from "node:crypto";
import { eq } from "drizzle-orm";
import { users } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { handle, jsonResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import {
  authRateLimitKey,
  consumeAnonAuthRateLimit,
  consumeAuthRateLimit,
} from "../../../lib/api/rate-limit.js";
import { getDataRuntime } from "../../../data/runtime.js";
import { frontendUrl } from "../../../lib/api/frontend-url.js";

export const config = { mode: "app" };

const forgotPasswordSchema = z.object({
  email: z.string().email(),
});

export async function action({ request }: { request: Request }) {
  return handle(async () => {
    const data = forgotPasswordSchema.parse(await readJsonBody(request));

    const clientKey = authRateLimitKey(request);
    if (clientKey !== null) {
      await consumeAuthRateLimit(clientKey);
    } else {
      await consumeAnonAuthRateLimit(data.email);
    }

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

    const runtime = await getDataRuntime();
    await runtime.queue.add("notification.send-email", {
      userId: user.id,
      email: user.email,
      subject: "Reset your Omi RSS password",
      template: "password-reset",
      data: {
        username: user.username,
        resetUrl: frontendUrl(`/reset-password?token=${resetToken}`),
      },
    });

    console.info(`Password reset requested for user: ${user.id}`);

    return jsonResponse({ message: "If an account exists, a password reset email has been sent." });
  });
}
