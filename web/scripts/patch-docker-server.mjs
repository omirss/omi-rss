// Post-build patch for the Docker adapter's generated server entry.
//
// dist/server.mjs serves static files (including the SPA shell at "/") from
// disk BEFORE the Neutron router runs, so the securityHeaders middleware in
// src/middleware.ts never sees those responses — only the hardcoded nosniff
// in streamFile() applied. This script injects the remaining baseline
// headers (frame-options, referrer-policy, CSP) into streamFile() so static
// responses match the middleware's set. Keep the CSP in sync with
// src/lib/api/security-headers.ts (which pins the theme-boot script hash).
// It also adds the .webmanifest -> text/manifest+json mapping the adapter's
// built-in MIME table lacks.

import { readFileSync, writeFileSync } from "node:fs";

const FILE = new URL("../dist/server.mjs", import.meta.url);

const source = readFileSync(FILE, "utf-8");

let patched = source;

// manifest.webmanifest must serve as a manifest type, not the
// application/octet-stream fallback (installability depends on it).
const MIME_ANCHOR = `const MIME_TYPES = {`;
const MIME_INJECT = `const MIME_TYPES = {
  ".webmanifest": "text/manifest+json",`;

if (!source.includes(".webmanifest")) {
  if (!source.includes(MIME_ANCHOR)) {
    console.error("patch-docker-server: MIME_TYPES anchor not found — adapter template changed?");
    process.exit(1);
  }
  patched = patched.replace(MIME_ANCHOR, MIME_INJECT);
}

const ANCHOR = `  res.setHeader("X-Content-Type-Options", "nosniff");`;

const INJECT = `  res.setHeader("X-Content-Type-Options", "nosniff");
  // Baseline security headers for pre-router static responses — mirrors
  // applySecurityHeaders() in src/lib/api/security-headers.ts.
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "strict-origin-when-cross-origin");
  res.setHeader(
    "Content-Security-Policy",
    [
      "default-src 'self'",
      "img-src * data: blob:",
      "style-src 'self' 'unsafe-inline'",
      "script-src 'self' 'sha256-H+OFh1VyaFdUp2DZ0/JE80euGbuc5IbtNuMztbdNQDg=' 'sha256-XyS7aKhg/od+bbo5UAzmpDM9o+H5sqLh3MV0x7hnZz8='",
    ].join("; ")
  );`;

if (!source.includes("X-Frame-Options")) {
  if (!source.includes(ANCHOR)) {
    console.error("patch-docker-server: anchor line not found — adapter template changed?");
    process.exit(1);
  }
  patched = patched.replace(ANCHOR, INJECT);
}

if (patched === source) {
  console.log("patch-docker-server: already patched");
  process.exit(0);
}

writeFileSync(FILE, patched, "utf-8");
console.log("patch-docker-server: security headers and webmanifest mime injected into static file path");
