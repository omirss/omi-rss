import jwt from "jsonwebtoken";

// Ported from server/src/services/auth.service.ts (v0.2.1): same claims,
// secrets and expiry windows so tokens interop with the Express server.

export interface RefreshTokenPayload {
  userId: string;
}

export const REFRESH_TOKEN_EXPIRES_IN = "30d";

export function signAccessToken(userId: string, email: string, username: string, role: string): string {
  return jwt.sign({ userId, email, username, role }, process.env.JWT_SECRET!, {
    expiresIn: (process.env.JWT_EXPIRES_IN || "7d") as jwt.SignOptions["expiresIn"],
  });
}

export function signRefreshToken(userId: string): string {
  return jwt.sign({ userId, type: "refresh" }, process.env.JWT_SECRET!, {
    expiresIn: REFRESH_TOKEN_EXPIRES_IN as jwt.SignOptions["expiresIn"],
  });
}

export function verifyRefreshToken(token: string): RefreshTokenPayload | null {
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET!) as jwt.JwtPayload;

    if (decoded.type !== "refresh" || typeof decoded.userId !== "string") {
      return null;
    }

    return { userId: decoded.userId };
  } catch {
    return null;
  }
}
