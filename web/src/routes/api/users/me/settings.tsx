import { z } from "zod";
import { eq } from "drizzle-orm";
import { users } from "../../../../data/db/schema.js";
import { getDb } from "../../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../../lib/api/errors.js";
import { readJsonBody } from "../../../../lib/api/body.js";
import { requireAuth } from "../../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const updateSettingsSchema = z.object({
  settings: z.record(z.any()),
});

export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };
    const data = updateSettingsSchema.parse(await readJsonBody(request));
    const db = await getDb();

    const [user] = await db
      .select({ settings: users.settings })
      .from(users)
      .where(eq(users.id, auth.id))
      .limit(1);

    if (!user) {
      throw new AppError("User not found", 404);
    }

    const newSettings = {
      ...((user.settings as object) || {}),
      ...data.settings,
    };

    const [updatedUser] = await db
      .update(users)
      .set({
        settings: newSettings,
        updatedAt: new Date(),
      })
      .where(eq(users.id, auth.id))
      .returning({
        id: users.id,
        settings: users.settings,
      });

    return jsonResponse({
      user: updatedUser,
      settings: updatedUser.settings,
    });
  });
}
