import { z } from "zod";
import bcrypt from "bcrypt";
import { eq } from "drizzle-orm";
import { users } from "../../../../data/db/schema.js";
import { getDb } from "../../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../../lib/api/errors.js";
import { readJsonBody } from "../../../../lib/api/body.js";
import { requireAuth } from "../../../../lib/api/auth.js";
import { bumpTokenVersion } from "../../../../lib/api/tokens.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const updatePasswordSchema = z.object({
  currentPassword: z.string(),
  newPassword: z.string().min(8).max(100),
});

export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };
    const data = updatePasswordSchema.parse(await readJsonBody(request));
    const db = await getDb();

    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.id, auth.id))
      .limit(1);

    if (!user) {
      throw new AppError("User not found", 404);
    }

    const isValidPassword = await bcrypt.compare(data.currentPassword, user.passwordHash || "");
    if (!isValidPassword) {
      throw new AppError("Current password is incorrect", 401);
    }

    const passwordHash = await bcrypt.hash(data.newPassword, parseInt(process.env.BCRYPT_ROUNDS || "10"));

    await db
      .update(users)
      .set({
        passwordHash,
        updatedAt: new Date(),
      })
      .where(eq(users.id, auth.id));

    // Same revocation as logout and password reset: a password change
    // invalidates every outstanding access AND refresh token.
    await bumpTokenVersion(auth.id);

    return jsonResponse({ message: "Password updated successfully" });
  });
}
