// Absolute origin for links embedded in emails (verification, password
// reset). FRONTEND_URL is the documented source, but an SMTP-enabled
// instance that never sets it must not emit `undefined/verify-email?...`
// links — fall back to the local PORT origin so links stay well-formed
// (with a boot warning from the email service).

export function frontendUrl(path: string): string {
  const base = process.env.FRONTEND_URL || `http://localhost:${process.env.PORT || "3000"}`;
  return `${base}${path}`;
}
