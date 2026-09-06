import { z } from "zod";
import bcrypt from "bcrypt";
import crypto from "node:crypto";
import { count, eq, or } from "drizzle-orm";
import { users } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import {
  authRateLimitKey,
  consumeAnonAuthRateLimit,
  consumeAuthRateLimit,
} from "../../../lib/api/rate-limit.js";
import { getDataRuntime } from "../../../data/runtime.js";
import { signAccessToken, signRefreshToken } from "../../../lib/api/tokens.js";

export const config = { mode: "app" };

// Email is optional (username+password sign-up). Empty string and null are
// tolerated as absent so client forms can send the field unconditionally.
const optionalEmail = z
  .union([z.string().email(), z.literal(""), z.null()])
  .optional()
  .transform((value) => (value ? value : undefined));

const registerSchema = z.object({
  email: optionalEmail,
  username: z.string().min(3).max(50),
  password: z.string().min(8).max(100),
  firstName: z.string().optional(),
  lastName: z.string().optional(),
});

export async function action({ request }: { request: Request }) {
  return handle(async () => {
    const data = registerSchema.parse(await readJsonBody(request));

    const clientKey = authRateLimitKey(request);
    if (clientKey !== null) {
      await consumeAuthRateLimit(clientKey);
    } else {
      await consumeAnonAuthRateLimit(`${data.email ?? ""}:${data.username}`);
    }

    const db = await getDb();

    // ALLOW_REGISTRATION=false closes sign-ups, but an empty instance always
    // allows the first user (bootstrap) so a fresh deploy is never locked out.
    if (process.env.ALLOW_REGISTRATION === "false") {
      const [{ value: userCount }] = await db.select({ value: count() }).from(users);
      if (userCount > 0) {
        throw new AppError("Registration is closed", 403);
      }
    }

    // Absent email must not match anything: eq(email, null) is never true in
    // SQL, but guarding explicitly keeps the username-only contract obvious.
    const conflict = data.email
      ? or(eq(users.email, data.email), eq(users.username, data.username))
      : eq(users.username, data.username);

    const [existingUser] = await db
      .select()
      .from(users)
      .where(conflict)
      .limit(1);

    if (existingUser) {
      // Generic message + kept 409 status (client contract): no account
      // existence oracle through the response body.
      throw new AppError("Registration failed", 409);
    }

    const passwordHash = await bcrypt.hash(data.password, parseInt(process.env.BCRYPT_ROUNDS || "10"));

    // No email -> no verification flow: null token, no queue job.
    const emailVerificationToken = data.email ? crypto.randomBytes(32).toString("hex") : null;

    const [newUser] = await db
      .insert(users)
      .values({
        email: data.email ?? null,
        username: data.username,
        passwordHash,
        firstName: data.firstName,
        lastName: data.lastName,
        emailVerificationToken,
      })
      .returning({
        id: users.id,
        email: users.email,
        username: users.username,
      });

    if (data.email) {
      const runtime = await getDataRuntime();
      await runtime.queue.add("notification.send-email", {
        userId: newUser.id,
        email: data.email,
        subject: "Verify your Omi RSS account",
        template: "email-verification",
        data: {
          username: data.username,
          verificationUrl: `${process.env.FRONTEND_URL}/verify-email?token=${emailVerificationToken}`,
        },
      });
    }

    const token = signAccessToken(newUser.id, newUser.email, newUser.username, "user", 0);
    const refreshToken = signRefreshToken(newUser.id, 0);

    console.info(`New user registered: ${newUser.id}`);

    return jsonResponse(
      {
        token,
        refreshToken,
        user: newUser,
      },
      201
    );
  });
}
