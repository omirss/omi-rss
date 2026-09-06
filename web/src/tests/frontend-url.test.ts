import { describe, it, expect, afterAll } from "vitest";
import { frontendUrl } from "../lib/api/frontend-url.js";

// Email link origin: FRONTEND_URL wins; without it links must still be
// well-formed (PORT origin fallback), never `undefined/...`.

const hadFrontendUrl = process.env.FRONTEND_URL;
const hadPort = process.env.PORT;

afterAll(() => {
  if (hadFrontendUrl === undefined) delete process.env.FRONTEND_URL;
  else process.env.FRONTEND_URL = hadFrontendUrl;
  if (hadPort === undefined) delete process.env.PORT;
  else process.env.PORT = hadPort;
});

describe("frontendUrl", () => {
  it("uses FRONTEND_URL when set", () => {
    process.env.FRONTEND_URL = "https://reader.example.com";
    expect(frontendUrl("/verify-email?token=abc")).toBe(
      "https://reader.example.com/verify-email?token=abc"
    );
  });

  it("falls back to the PORT origin when FRONTEND_URL is unset", () => {
    delete process.env.FRONTEND_URL;
    process.env.PORT = "3910";
    expect(frontendUrl("/reset-password?token=abc")).toBe(
      "http://localhost:3910/reset-password?token=abc"
    );
  });

  it("falls back to port 3000 when both are unset", () => {
    delete process.env.FRONTEND_URL;
    delete process.env.PORT;
    expect(frontendUrl("/verify-email?token=abc")).toBe(
      "http://localhost:3000/verify-email?token=abc"
    );
  });
});
