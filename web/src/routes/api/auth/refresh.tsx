import { z } from "zod";
import { eq } from "drizzle-orm";
import { users } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { consumeAuthRateLimit } from "../../../lib/api/rate-limit.js";
import {
  signAccessToken,
  signRefreshToken,
  tokenVersionMatches,
  verifyRefreshToken,
} from "../../../lib/api/tokens.js";

export const config = { mode: "app" };

const refreshSchema = z.object({
  refreshToken: z.string(),
});

export async function action({ request }: { request: Request }) {
  return handle(async () => {
    const data = refreshSchema.parse(await readJsonBody(request));

    const decoded = verifyRefreshToken(data.refreshToken);

    if (!decoded) {
      throw new AppError("Invalid refresh token", 401);
    }

    const db = await getDb();

    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.id, decoded.userId))
      .limit(1);

    if (!user || !user.isActive) {
      throw new AppError("Invalid refresh token", 401);
    }

    if (!tokenVersionMatches(decoded.tokenVersion, user.tokenVersion)) {
      throw new AppError("Invalid refresh token", 401);
    }

    await consumeAuthRateLimit(`refresh:${user.id}`);

    const tokenVersion = user.tokenVersion ?? 0;
    const token = signAccessToken(user.id, user.email, user.username, user.role, tokenVersion);
    const refreshToken = signRefreshToken(user.id, tokenVersion);

    return jsonResponse({ token, refreshToken });
  });
}
