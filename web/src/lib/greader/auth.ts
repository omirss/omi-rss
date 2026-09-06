import type { MiddlewareFn } from "@neutron-build/core";
import { eq } from "drizzle-orm";
import { users } from "../../data/db/schema.js";
import { getDb } from "../api/db.js";
import { AppError } from "../api/errors.js";
import { tokenVersionMatches, verifyGreaderToken } from "../api/tokens.js";
import { consumeGreaderRateLimit } from "./limit.js";
import {
  GREADER_CORS_HEADERS,
  greaderErrorResponse,
  greaderTextResponse,
  greaderUnauthorized,
  greaderBadPostToken,
  type GreaderParams,
} from "./http.js";

// greader-local auth wrapper. Deliberately NOT requireAuth:
//   - parses `Authorization: GoogleLogin auth=<token>` (the greader header),
//   - verifies the greader-auth JWT (type claim set, so web access tokens
//     and refresh tokens are rejected here, and greader tokens are rejected
//     by requireAuth),
//   - re-checks tokenVersion (logout/password change revokes greader tokens),
//   - consumes the 600/15min greader bucket instead of the 100/15min web
//     bucket — sync clients burst far past 100 requests during initial sync.
//
// ClientLogin and CORS preflight skip auth here.

export interface GreaderUser {
  id: string;
  email: string | null;
  username: string;
  role: string;
  tokenVersion: number;
  createdAt: Date;
}

export function parseGoogleLoginAuth(header: string | null): string | null {
  if (!header || !header.startsWith("GoogleLogin auth=")) {
    return null;
  }
  // The token is echoed verbatim; may contain / + = characters. Everything
  // after the prefix, no URL-decoding.
  const token = header.slice("GoogleLogin auth=".length);
  return token.length > 0 ? token : null;
}

export const requireGreaderAuth: MiddlewareFn = async (request, context, next) => {
  try {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: GREADER_CORS_HEADERS });
    }
    const pathname = new URL(request.url).pathname;
    if (pathname === "/api/greader/accounts/ClientLogin") {
      return next();
    }

    const token = parseGoogleLoginAuth(request.headers.get("authorization"));
    if (!token) {
      return greaderUnauthorized();
    }

    const claims = verifyGreaderToken(token, "greader-auth");
    if (!claims) {
      return greaderUnauthorized();
    }

    const db = await getDb();
    const [row] = await db
      .select({
        id: users.id,
        email: users.email,
        username: users.username,
        role: users.role,
        isActive: users.isActive,
        tokenVersion: users.tokenVersion,
        createdAt: users.createdAt,
      })
      .from(users)
      .where(eq(users.id, claims.userId))
      .limit(1);

    if (!row || !row.isActive) {
      return greaderUnauthorized();
    }

    if (!tokenVersionMatches(claims.tokenVersion, row.tokenVersion)) {
      return greaderUnauthorized();
    }

    await consumeGreaderRateLimit(row.id);

    context.user = {
      id: row.id,
      email: row.email,
      username: row.username,
      role: row.role,
      tokenVersion: row.tokenVersion ?? 0,
      createdAt: row.createdAt,
    };

    return next();
  } catch (error) {
    if (error instanceof AppError) {
      return greaderTextResponse(error.message, error.statusCode);
    }
    return greaderErrorResponse(error);
  }
};

// T (post) token policy: verify when present and non-empty; tolerate
// absent/empty (FeedMe omits it — FreshRSS tolerates). Present-but-invalid
// returns the 401 bad-token Response so clients refetch /token and retry.
// The XSRF threat model does not apply to a header-authenticated, cookie-less
// API, so leniency costs no real security.
export function verifyGreaderPostToken(params: GreaderParams, user: GreaderUser): Response | null {
  const token = params.get("T");
  if (token === null || token === "") {
    return null;
  }
  const claims = verifyGreaderToken(token, "greader-post");
  if (!claims || claims.userId !== user.id || !tokenVersionMatches(claims.tokenVersion, user.tokenVersion)) {
    return greaderBadPostToken();
  }
  return null;
}

export function getContextGreaderUser(context: Record<string, unknown>): GreaderUser {
  return context.user as GreaderUser;
}
