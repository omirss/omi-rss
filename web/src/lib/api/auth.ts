import type { MiddlewareFn } from "@neutron-build/core";
import jwt from "jsonwebtoken";
import { eq } from "drizzle-orm";
import { users } from "../../data/db/schema.js";
import { getDb } from "./db.js";
import { AppError } from "./errors.js";

// Ported from server/src/middleware/authentication.ts (v0.2.1) as a Neutron
// route middleware. Same 401 bodies (no timestamp — these bypassed the
// Express errorHandler), same user shape on context.

export interface AuthUser {
  id: string;
  email: string;
  username: string;
  role: string;
}

interface JwtPayload {
  userId: string;
  email: string;
  username: string;
  role: string;
}

function unauthorized(message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status: 401,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

export const requireAuth: MiddlewareFn = async (request, context, next) => {
  try {
    const authHeader = request.headers.get("authorization");
    if (!authHeader) {
      return unauthorized("No authorization header");
    }

    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : authHeader;
    if (!token) {
      return unauthorized("No token provided");
    }

    const decoded = jwt.verify(token, process.env.JWT_SECRET!) as JwtPayload;

    const db = await getDb();
    const [user] = await db
      .select({
        id: users.id,
        email: users.email,
        username: users.username,
        role: users.role,
        isActive: users.isActive,
      })
      .from(users)
      .where(eq(users.id, decoded.userId))
      .limit(1);

    if (!user) {
      return unauthorized("User not found");
    }

    if (!user.isActive) {
      return unauthorized("Account is disabled");
    }

    context.user = {
      id: user.id,
      email: user.email,
      username: user.username,
      role: user.role,
    };

    return next();
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      return unauthorized("Token expired");
    }
    if (error instanceof jwt.JsonWebTokenError) {
      return unauthorized("Invalid token");
    }

    console.error("Authentication error:", error);
    return new Response(JSON.stringify({ error: "Authentication failed" }), {
      status: 500,
      headers: { "Content-Type": "application/json; charset=utf-8" },
    });
  }
};

export function getContextUser(context: Record<string, unknown>): AuthUser {
  const user = context.user as AuthUser | undefined;
  if (!user) {
    throw new AppError("Not authenticated", 401);
  }
  return user;
}
