import type { MiddlewareFn } from "@neutron-build/core";
import { validateAuthBootEnv } from "./tokens.js";

// v0.3.1 security audit: baseline security headers on every app-route
// response (the webui, the API and uploads alike).
//
// CSP note: script-src allows 'self', a sha256 hash of the inline theme
// bootstrap injected by routes/_layout.tsx (THEME_BOOT_SCRIPT), and a hash
// of the fixed speculation-rules payload the runtime injects into app-tier
// documents (renderStaticLinkSpeculationRules emits one closed, constant
// JSON structure). Without the theme hash the theme boot is blocked and the
// UI flashes the default theme on every load; hash source expressions MUST
// be single-quoted or the whole source is ignored. No 'unsafe-inline' for
// scripts.
const THEME_BOOT_SCRIPT_SHA256 = "'sha256-H+OFh1VyaFdUp2DZ0/JE80euGbuc5IbtNuMztbdNQDg='";
const SPECULATION_RULES_SHA256 = "'sha256-XyS7aKhg/od+bbo5UAzmpDM9o+H5sqLh3MV0x7hnZz8='";

const CONTENT_SECURITY_POLICY = [
  "default-src 'self'",
  "img-src * data: blob:",
  "style-src 'self' 'unsafe-inline'",
  `script-src 'self' ${THEME_BOOT_SCRIPT_SHA256} ${SPECULATION_RULES_SHA256}`,
].join("; ");

export function applySecurityHeaders(response: Response): Response {
  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set("X-Frame-Options", "DENY");
  response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  response.headers.set("Content-Security-Policy", CONTENT_SECURITY_POLICY);
  return response;
}

export const securityHeaders: MiddlewareFn = async (_request, _context, next) => {
  const response = await next();
  return applySecurityHeaders(response);
};

// Module-scope boot gate: this file loads once at server startup through the
// global middleware import, so production refuses to start on a weak
// JWT_SECRET before serving a single request.
validateAuthBootEnv();
