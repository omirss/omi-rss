import { z } from "zod";
import bcrypt from "bcrypt";
import crypto from "node:crypto";
import { count, eq, or, sql } from "drizzle-orm";
import { users } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { optionalEmail } from "../../../lib/api/email-field.js";
import {
  authRateLimitKey,
  consumeAnonAuthRateLimit,
  consumeAuthRateLimit,
} from "../../../lib/api/rate-limit.js";
import { getDataRuntime } from "../../../data/runtime.js";
import { frontendUrl } from "../../../lib/api/frontend-url.js";
import { signAccessToken, signRefreshToken } from "../../../lib/api/tokens.js";

export const config = { mode: "app" };

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
    const passwordHash = await bcrypt.hash(data.password, parseInt(process.env.BCRYPT_ROUNDS || "10"));
    const emailVerificationToken = data.email ? crypto.randomBytes(32).toString("hex") : null;

    const newUser = await db.transaction(async (tx) => {
      // Lock before the count snapshot so only one connection can bootstrap.
      if (process.env.ALLOW_REGISTRATION === "false") {
        await tx.execute(sql`LOCK TABLE ${users} IN SHARE ROW EXCLUSIVE MODE`);
        const [{ value: userCount }] = await tx.select({ value: count() }).from(users);
        if (userCount > 0) {
          throw new AppError("Registration is closed", 403);
        }
      }

      const conflict = data.email
        ? or(eq(users.email, data.email), eq(users.username, data.username))
        : eq(users.username, data.username);

      const [existingUser] = await tx
        .select()
        .from(users)
        .where(conflict)
        .limit(1);

      if (existingUser) {
        throw new AppError("Registration failed", 409);
      }

      const [newUser] = await tx
        .insert(users)
        .values({
          email: data.email ?? null,
          username: data.username,
          passwordHash,
          firstName: data.firstName,
          lastName: data.lastName,
          emailVerificationToken,
        })
        .onConflictDoNothing()
        .returning({
          id: users.id,
          email: users.email,
          username: users.username,
        });
      // Concurrent open registrations use the same non-enumerating response.
      if (!newUser) throw new AppError("Registration failed", 409);
      return newUser;
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
          verificationUrl: frontendUrl(`/verify-email?token=${emailVerificationToken}`),
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
