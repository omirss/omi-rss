import { z } from "zod";
import bcrypt from "bcrypt";
import { eq } from "drizzle-orm";
import { users } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, handleLoader, jsonResponse, noContent } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const updateProfileSchema = z.object({
  firstName: z.string().optional(),
  lastName: z.string().optional(),
  username: z.string().min(3).max(50).optional(),
});

export async function loader({ context }: { context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };
    const db = await getDb();

    const [user] = await db
      .select({
        id: users.id,
        email: users.email,
        username: users.username,
        firstName: users.firstName,
        lastName: users.lastName,
        avatarUrl: users.avatarUrl,
        role: users.role,
        emailVerified: users.emailVerified,
        settings: users.settings,
        createdAt: users.createdAt,
        updatedAt: users.updatedAt,
        lastLoginAt: users.lastLoginAt,
      })
      .from(users)
      .where(eq(users.id, auth.id))
      .limit(1);

    if (!user) {
      throw new AppError("User not found", 404);
    }

    return jsonResponse({ user });
  });
}

export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };

    if (request.method === "DELETE") {
      const body = await readJsonBody(request);
      const { password } = body as { password?: string };

      if (!password) {
        throw new AppError("Password required to delete account", 400);
      }

      const db = await getDb();

      const [user] = await db
        .select()
        .from(users)
        .where(eq(users.id, auth.id))
        .limit(1);

      if (!user) {
        throw new AppError("User not found", 404);
      }

      const isValidPassword = await bcrypt.compare(password, user.passwordHash || "");
      if (!isValidPassword) {
        throw new AppError("Password is incorrect", 401);
      }

      await db
        .delete(users)
        .where(eq(users.id, auth.id));

      return noContent();
    }

    const data = updateProfileSchema.parse(await readJsonBody(request));
    const db = await getDb();

    if (data.username) {
      const [existingUser] = await db
        .select()
        .from(users)
        .where(eq(users.username, data.username))
        .limit(1);

      if (existingUser && existingUser.id !== auth.id) {
        throw new AppError("Username already taken", 409);
      }
    }

    const [updatedUser] = await db
      .update(users)
      .set({
        ...data,
        updatedAt: new Date(),
      })
      .where(eq(users.id, auth.id))
      .returning({
        id: users.id,
        email: users.email,
        username: users.username,
        firstName: users.firstName,
        lastName: users.lastName,
        avatarUrl: users.avatarUrl,
      });

    return jsonResponse({ user: updatedUser });
  });
}
