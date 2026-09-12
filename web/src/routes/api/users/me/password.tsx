import { z } from "zod";
import bcrypt from "bcrypt";
import { and, eq, sql } from "drizzle-orm";
import { users } from "../../../../data/db/schema.js";
import { getDb } from "../../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../../lib/api/errors.js";
import { readJsonBody } from "../../../../lib/api/body.js";
import { requireAuth } from "../../../../lib/api/auth.js";

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

    // One atomic statement conditioned on the verified hash: password
    // write, pending-reset-token clear and token-version bump (revoking
    // every outstanding access AND refresh token, same as logout and
    // password reset) commit together. A concurrent password change
    // invalidates this request's precondition and it must re-authenticate.
    const updated = await db
      .update(users)
      .set({
        passwordHash,
        passwordResetToken: null,
        passwordResetExpires: null,
        tokenVersion: sql`${users.tokenVersion} + 1`,
        updatedAt: new Date(),
      })
      .where(
        and(
          eq(users.id, auth.id),
          eq(users.passwordHash, user.passwordHash!),
        ),
      )
      .returning({ id: users.id });

    if (updated.length === 0) {
      throw new AppError("Password was changed concurrently; sign in and try again", 409);
    }

    return jsonResponse({ message: "Password updated successfully" });
  });
}
