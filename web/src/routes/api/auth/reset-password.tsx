import { z } from "zod";
import bcrypt from "bcrypt";
import { and, eq, gt, sql } from "drizzle-orm";
import { users } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";

export const config = { mode: "app" };

const resetPasswordSchema = z.object({
  token: z.string(),
  password: z.string().min(8).max(100),
});

export async function action({ request }: { request: Request }) {
  return handle(async () => {
    const data = resetPasswordSchema.parse(await readJsonBody(request));

    const db = await getDb();

    const passwordHash = await bcrypt.hash(data.password, parseInt(process.env.BCRYPT_ROUNDS || "10"));

    // Single conditional UPDATE keyed on the capability: password write,
    // token consumption and token-version bump (revoking every outstanding
    // access/refresh token) commit atomically, and a token can only ever be
    // consumed once — concurrent resets see zero rows here.
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
          eq(users.passwordResetToken, data.token),
          gt(users.passwordResetExpires, new Date()),
        ),
      )
      .returning({ id: users.id });

    if (updated.length === 0) {
      throw new AppError("Invalid or expired reset token", 400);
    }

    console.info(`Password reset for user: ${updated[0].id}`);

    return jsonResponse({ message: "Password reset successfully" });
  });
}
