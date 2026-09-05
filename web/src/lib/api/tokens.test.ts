import { describe, it, expect, beforeAll } from "vitest";
import jwt from "jsonwebtoken";
import {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} from "./tokens.js";

// Ported from Express tests/unit/services/auth.service.test.ts — same claims,
// secrets and expiry contracts, exercised against the real jwt library.

beforeAll(() => {
  process.env.JWT_SECRET = "test-secret";
});

function decode(token: string): jwt.JwtPayload {
  return jwt.decode(token) as jwt.JwtPayload;
}

describe("auth token functions", () => {
  describe("signAccessToken", () => {
    it("should sign an access token with user claims", () => {
      const token = signAccessToken("123", "test@example.com", "testuser", "user");

      const payload = decode(token);
      expect(payload.userId).toBe("123");
      expect(payload.email).toBe("test@example.com");
      expect(payload.username).toBe("testuser");
      expect(payload.role).toBe("user");
      expect(payload.type).toBeUndefined();
    });

    it("should use the configured expiry window", () => {
      const token = signAccessToken("123", "test@example.com", "testuser", "user");

      const payload = decode(token);
      const days = (payload.exp! - payload.iat!) / (60 * 60 * 24);
      expect(days).toBe(7);
    });

    it("should verify with the same secret", () => {
      const token = signAccessToken("123", "test@example.com", "testuser", "user");

      const payload = jwt.verify(token, "test-secret") as jwt.JwtPayload;
      expect(payload.userId).toBe("123");
    });
  });

  describe("refresh tokens", () => {
    it("should sign a refresh token with a refresh type claim and 30d expiry", () => {
      const token = signRefreshToken("123");

      const payload = decode(token);
      expect(payload.userId).toBe("123");
      expect(payload.type).toBe("refresh");
      expect((payload.exp! - payload.iat!) / (60 * 60 * 24)).toBe(30);
    });

    it("should verify a valid refresh token", () => {
      const token = signRefreshToken("123");

      expect(verifyRefreshToken(token)).toEqual({ userId: "123" });
    });

    it("should reject an access token used as a refresh token", () => {
      const accessToken = signAccessToken("123", "test@example.com", "testuser", "user");

      expect(verifyRefreshToken(accessToken)).toBeNull();
    });

    it("should reject a refresh token without a userId", () => {
      const token = jwt.sign({ type: "refresh" }, "test-secret");

      expect(verifyRefreshToken(token)).toBeNull();
    });

    it("should return null for an invalid token", () => {
      expect(verifyRefreshToken("invalidtoken")).toBeNull();
    });
  });
});
