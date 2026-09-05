import { eq } from "drizzle-orm";
import { users } from "../../../../data/db/schema.js";
import { getDb } from "../../../../lib/api/db.js";
import { AppError, handle, handleLoader, jsonResponse } from "../../../../lib/api/errors.js";

export const config = { mode: "app" };

export async function loader({ params }: { params: Record<string, string> }) {
  return handleLoader(async () => {
    const { token } = params;

    const db = await getDb();

    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.emailVerificationToken, token))
      .limit(1);

    if (!user) {
      throw new AppError("Invalid verification token", 400);
    }

    await db
      .update(users)
      .set({
        emailVerified: true,
        emailVerificationToken: null,
      })
      .where(eq(users.id, user.id));

    console.info(`Email verified for user: ${user.id}`);

    return jsonResponse({ message: "Email verified successfully" });
  });
}
