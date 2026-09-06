import jwt from "jsonwebtoken";
import { eq, sql } from "drizzle-orm";
import { users } from "../../data/db/schema.js";
import { getDb } from "./db.js";

// Ported from Express services/auth.service.ts (v0.2.1): same claims,
// secrets and expiry windows so tokens interop with the Express server.
//
// v0.3.1 security audit additions:
//   - tokenVersion claim (mirrors users.token_version, default 0) on BOTH
//     token types; requireAuth and the refresh route reject mismatches, so
//     bumping the column invalidates every outstanding token for the user.
//   - Access tokens carry NO `type` claim; verifyAccessTokenClaims rejects
//     any token that has one (refresh-as-access).
//   - validateAuthBootEnv refuses to boot in production with a missing or
//     weak (< 32 chars) JWT_SECRET.

export interface RefreshTokenPayload {
  userId: string;
  tokenVersion: number;
}

export const REFRESH_TOKEN_EXPIRES_IN = "30d";

export function normalizeTokenVersion(value: unknown): number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : 0;
}

export function signAccessToken(
  userId: string,
  email: string | null,
  username: string,
  role: string,
  tokenVersion: number = 0
): string {
  return jwt.sign({ userId, email, username, role, tokenVersion }, process.env.JWT_SECRET!, {
    expiresIn: (process.env.JWT_EXPIRES_IN || "7d") as jwt.SignOptions["expiresIn"],
  });
}

export function signRefreshToken(userId: string, tokenVersion: number = 0): string {
  return jwt.sign({ userId, type: "refresh", tokenVersion }, process.env.JWT_SECRET!, {
    expiresIn: REFRESH_TOKEN_EXPIRES_IN as jwt.SignOptions["expiresIn"],
  });
}

export interface AccessTokenClaims {
  userId: string;
  email: string;
  username: string;
  role: string;
  tokenVersion: number;
}

// Validates the claim shape of a VERIFIED (signature-checked) access token.
// Rejects refresh tokens (any `type` claim — access tokens carry none) and
// tokens without a userId.
export function verifyAccessTokenClaims(decoded: unknown): AccessTokenClaims | null {
  if (typeof decoded !== "object" || decoded === null) {
    return null;
  }
  const payload = decoded as Record<string, unknown>;
  if (payload.type !== undefined) {
    return null;
  }
  if (typeof payload.userId !== "string" || payload.userId.length === 0) {
    return null;
  }
  return {
    userId: payload.userId,
    email: typeof payload.email === "string" ? payload.email : "",
    username: typeof payload.username === "string" ? payload.username : "",
    role: typeof payload.role === "string" ? payload.role : "user",
    tokenVersion: normalizeTokenVersion(payload.tokenVersion),
  };
}

export function tokenVersionMatches(claim: unknown, current: unknown): boolean {
  return normalizeTokenVersion(claim) === normalizeTokenVersion(current);
}

// v0.6.0 greader API (Google Reader compatible) tokens. They carry a `type`
// claim, mirroring the refresh-token convention: verifyAccessTokenClaims
// rejects any token with a `type` claim, so greader tokens cannot be replayed
// against the web API, and verifyGreaderToken rejects typeless web access
// tokens, so those cannot be replayed against the greader API.
//
// Auth token: long-lived (7d), the ClientLogin `Auth=` value.
// Post token ("T"): 30 minutes, matches the Google Reader contract.

export const GREADER_AUTH_TOKEN_EXPIRES_IN = "7d";
export const GREADER_POST_TOKEN_EXPIRES_IN = "30m";

export type GreaderTokenType = "greader-auth" | "greader-post";

export function signGreaderAuthToken(
  userId: string,
  email: string | null,
  username: string,
  role: string,
  tokenVersion: number = 0
): string {
  return jwt.sign(
    { userId, email, username, role, tokenVersion, type: "greader-auth" },
    process.env.JWT_SECRET!,
    { expiresIn: GREADER_AUTH_TOKEN_EXPIRES_IN as jwt.SignOptions["expiresIn"] }
  );
}

export function signGreaderPostToken(userId: string, tokenVersion: number = 0): string {
  return jwt.sign({ userId, tokenVersion, type: "greader-post" }, process.env.JWT_SECRET!, {
    expiresIn: GREADER_POST_TOKEN_EXPIRES_IN as jwt.SignOptions["expiresIn"],
  });
}

export interface GreaderTokenPayload {
  userId: string;
  tokenVersion: number;
}

export function verifyGreaderToken(token: string, expectedType: GreaderTokenType): GreaderTokenPayload | null {
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET!) as jwt.JwtPayload;
    if (decoded.type !== expectedType || typeof decoded.userId !== "string" || decoded.userId.length === 0) {
      return null;
    }
    return { userId: decoded.userId, tokenVersion: normalizeTokenVersion(decoded.tokenVersion) };
  } catch {
    return null;
  }
}

export function verifyRefreshToken(token: string): RefreshTokenPayload | null {
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET!) as jwt.JwtPayload;

    if (decoded.type !== "refresh" || typeof decoded.userId !== "string") {
      return null;
    }

    return { userId: decoded.userId, tokenVersion: normalizeTokenVersion(decoded.tokenVersion) };
  } catch {
    return null;
  }
}

// Invalidate every outstanding token (access AND refresh) for a user by
// bumping users.token_version. Wired into logout, password reset and
// account delete; exported for the password-change route owner.
export async function bumpTokenVersion(userId: string): Promise<void> {
  const db = await getDb();
  await db
    .update(users)
    .set({ tokenVersion: sql`${users.tokenVersion} + 1` })
    .where(eq(users.id, userId));
}

// Production boot gate: refuse to start with a missing or weak JWT secret.
// Called from the global middleware module (server boot) and the worker
// entry. Exits the process — a misconfigured secret in prod must not serve.
export function validateAuthBootEnv(): void {
  if (process.env.NODE_ENV !== "production") {
    return;
  }
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    console.error("FATAL: JWT_SECRET is not set. Refusing to boot in production.");
    process.exit(1);
  }
  if (secret.length < 32) {
    console.error(
      `FATAL: JWT_SECRET is only ${secret.length} characters; at least 32 required in production. Refusing to boot.`
    );
    process.exit(1);
  }
}
