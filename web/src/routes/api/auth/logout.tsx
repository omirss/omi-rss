import { requireAuth } from "../../../lib/api/auth.js";
import { handle, jsonResponse } from "../../../lib/api/errors.js";
import { bumpTokenVersion } from "../../../lib/api/tokens.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

// Self-hosted v0.3.1 semantics: logout invalidates ALL sessions for the
// user (tokenVersion bump) — both the access and refresh tokens of every
// outstanding session stop verifying. Acceptable for the single-user /
// small-team self-hosted audience; per-session revocation needs a
// server-side session store.
export async function action({ context }: { context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };

    await bumpTokenVersion(auth.id);

    console.info(`User logged out: ${auth.id}`);

    return jsonResponse({ message: "Logged out successfully" });
  });
}
