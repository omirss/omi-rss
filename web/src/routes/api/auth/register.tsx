import { z } from "zod";
import bcrypt from "bcrypt";
import crypto from "node:crypto";
import { eq, or } from "drizzle-orm";
import { users } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { authRateLimitKey, consumeAuthRateLimit } from "../../../lib/api/rate-limit.js";
import { sendEmail } from "../../../services/email.js";
import { signAccessToken, signRefreshToken } from "../../../lib/api/tokens.js";

export const config = { mode: "app" };

const registerSchema = z.object({
  email: z.string().email(),
  username: z.string().min(3).max(50),
  password: z.string().min(8).max(100),
  firstName: z.string().optional(),
  lastName: z.string().optional(),
});

export async function action({ request }: { request: Request }) {
  return handle(async () => {
    await consumeAuthRateLimit(authRateLimitKey(request));

    const data = registerSchema.parse(await readJsonBody(request));

    const db = await getDb();

    const [existingUser] = await db
      .select()
      .from(users)
      .where(or(eq(users.email, data.email), eq(users.username, data.username)))
      .limit(1);

    if (existingUser) {
      throw new AppError("User already exists", 409);
    }

    const passwordHash = await bcrypt.hash(data.password, parseInt(process.env.BCRYPT_ROUNDS || "10"));

    const emailVerificationToken = crypto.randomBytes(32).toString("hex");

    const [newUser] = await db
      .insert(users)
      .values({
        email: data.email,
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

    await sendEmail({
      to: data.email,
      subject: "Verify your Omi RSS account",
      template: "email-verification",
      data: {
        username: data.username,
        verificationUrl: `${process.env.FRONTEND_URL}/verify-email?token=${emailVerificationToken}`,
      },
    });

    const token = signAccessToken(newUser.id, newUser.email, newUser.username, "user");
    const refreshToken = signRefreshToken(newUser.id);

    console.info(`New user registered: ${newUser.email}`);

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
