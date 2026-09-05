import type { MiddlewareFn } from "@neutron-build/core";
import jwt from "jsonwebtoken";
import { eq } from "drizzle-orm";
import { users } from "../../data/db/schema.js";
import { getDb } from "./db.js";
import { AppError } from "./errors.js";
import { tokenVersionMatches, verifyAccessTokenClaims } from "./tokens.js";
import { consumeUserRateLimit } from "./rate-limit.js";

// Ported from Express middleware/authentication.ts (v0.2.1) as a Neutron
// route middleware. Same 401 bodies (no timestamp — these bypassed the
// Express errorHandler), same user shape on context.
//
// v0.3.1 security audit hardening:
//   - Refresh tokens are rejected: access tokens carry no `type` claim, so
//     any token with one is refused (refresh-as-access).
//   - The token's tokenVersion claim must match users.token_version;
//     bumping the column (logout, password reset/change, account delete)
//     invalidates all outstanding tokens.
//   - After verification the request consumes a per-user rate-limit bucket
//     (the per-client keying replacement for direct exposure).

export interface AuthUser {
  id: string;
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

    let decoded: unknown;
    try {
      decoded = jwt.verify(token, process.env.JWT_SECRET!);
    } catch (error) {
      if (error instanceof jwt.TokenExpiredError) {
        return unauthorized("Token expired");
      }
      if (error instanceof jwt.JsonWebTokenError) {
        return unauthorized("Invalid token");
      }
      throw error;
    }

    const claims = verifyAccessTokenClaims(decoded);
    if (!claims) {
      return unauthorized("Invalid token");
    }

    const db = await getDb();
    const [user] = await db
      .select({
        id: users.id,
        email: users.email,
        username: users.username,
        role: users.role,
        isActive: users.isActive,
        tokenVersion: users.tokenVersion,
      })
      .from(users)
      .where(eq(users.id, claims.userId))
      .limit(1);

    if (!user) {
      return unauthorized("User not found");
    }

    if (!user.isActive) {
      return unauthorized("Account is disabled");
    }

    if (!tokenVersionMatches(claims.tokenVersion, user.tokenVersion)) {
      return unauthorized("Invalid token");
    }

    await consumeUserRateLimit(user.id);

    context.user = {
      id: user.id,
      email: user.email,
      username: user.username,
      role: user.role,
    };

    return next();
  } catch (error) {
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
