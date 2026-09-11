// Postgres unique-violation (23505) detection for error paths where the
// (user_id, url) unique index on feeds is the real duplicate check.
export function isUniqueViolation(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    (error as { code?: unknown }).code === "23505"
  );
}
