import { z } from "zod";
import bcrypt from "bcrypt";
import { eq, or } from "drizzle-orm";
import { users } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { authRateLimitKey, consumeAuthRateLimit } from "../../../lib/api/rate-limit.js";
import { signAccessToken, signRefreshToken } from "../../../lib/api/tokens.js";

export const config = { mode: "app" };

const loginSchema = z.object({
  emailOrUsername: z.string(),
  password: z.string(),
});

export async function action({ request }: { request: Request }) {
  return handle(async () => {
    await consumeAuthRateLimit(authRateLimitKey(request));

    const data = loginSchema.parse(await readJsonBody(request));

    const db = await getDb();

    const [user] = await db
      .select()
      .from(users)
      .where(
        or(
          eq(users.email, data.emailOrUsername),
          eq(users.username, data.emailOrUsername),
        ),
      )
      .limit(1);

    if (!user) {
      throw new AppError("Invalid credentials", 401);
    }

    if (!user.isActive) {
      throw new AppError("Account is disabled", 401);
    }

    const isValidPassword = await bcrypt.compare(data.password, user.passwordHash || "");
    if (!isValidPassword) {
      throw new AppError("Invalid credentials", 401);
    }

    await db
      .update(users)
      .set({ lastLoginAt: new Date() })
      .where(eq(users.id, user.id));

    const token = signAccessToken(user.id, user.email, user.username, user.role);
    const refreshToken = signRefreshToken(user.id);

    console.info(`User logged in: ${user.email}`);

    return jsonResponse({
      token,
      refreshToken,
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        firstName: user.firstName,
        lastName: user.lastName,
        avatarUrl: user.avatarUrl,
        role: user.role,
        emailVerified: user.emailVerified,
        settings: user.settings,
      },
    });
  });
}
