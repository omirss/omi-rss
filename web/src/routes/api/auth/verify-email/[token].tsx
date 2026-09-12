import { eq } from "drizzle-orm";
import { users } from "../../../../data/db/schema.js";
import { getDb } from "../../../../lib/api/db.js";
import { AppError, handle, handleLoader, jsonResponse } from "../../../../lib/api/errors.js";

export const config = { mode: "app" };

export async function loader({ params }: { params: Record<string, string> }) {
  return handleLoader(async () => {
    const { token } = params;

    const db = await getDb();

    // Single conditional UPDATE keyed on the token: a verification request
    // in flight while the profile installs a new email + new token can
    // never mark the NEW address verified or destroy its pending token.
    // Replays see zero rows.
    const updated = await db
      .update(users)
      .set({
        emailVerified: true,
        emailVerificationToken: null,
        updatedAt: new Date(),
      })
      .where(eq(users.emailVerificationToken, token))
      .returning({ id: users.id });

    if (updated.length === 0) {
      throw new AppError("Invalid verification token", 400);
    }

    console.info(`Email verified for user: ${updated[0].id}`);

    return jsonResponse({ message: "Email verified successfully" });
  });
}
