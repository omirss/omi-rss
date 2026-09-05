import { z } from "zod";
import bcrypt from "bcrypt";
import { eq } from "drizzle-orm";
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

    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.passwordResetToken, data.token))
      .limit(1);

    if (!user || !user.passwordResetExpires || user.passwordResetExpires < new Date()) {
      throw new AppError("Invalid or expired reset token", 400);
    }

    const passwordHash = await bcrypt.hash(data.password, parseInt(process.env.BCRYPT_ROUNDS || "10"));

    await db
      .update(users)
      .set({
        passwordHash,
        passwordResetToken: null,
        passwordResetExpires: null,
      })
      .where(eq(users.id, user.id));

    console.info(`Password reset for user: ${user.email}`);

    return jsonResponse({ message: "Password reset successfully" });
  });
}
