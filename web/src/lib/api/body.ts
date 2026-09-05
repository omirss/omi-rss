// Express's express.json() equivalent: parses the raw body as JSON, defaults
// to {} when empty (matching express.json's req.body default), and lets a
// SyntaxError surface so errorResponse maps it like the Express server did.

export async function readJsonBody(request: Request): Promise<Record<string, unknown>> {
  const raw = await request.text();
  if (!raw) {
    return {};
  }
  return JSON.parse(raw) as Record<string, unknown>;
}
