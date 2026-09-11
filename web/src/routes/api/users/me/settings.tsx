import { z } from "zod";
import { eq, sql } from "drizzle-orm";
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

    // Merge inside the UPDATE against the locked current row (jsonb concat
    // has the same semantics as the JS spread) — a read-merge-write in JS
    // lets two concurrent PUTs silently discard each other's keys.
    const [updatedUser] = await db
      .update(users)
      .set({
        settings: sql`COALESCE(${users.settings}, '{}'::jsonb) || ${JSON.stringify(data.settings)}::jsonb`,
        updatedAt: new Date(),
      })
      .where(eq(users.id, auth.id))
      .returning({
        id: users.id,
        settings: users.settings,
      });

    if (!updatedUser) {
      throw new AppError("User not found", 404);
    }

    return jsonResponse({
      user: updatedUser,
      settings: updatedUser.settings,
    });
  });
}
