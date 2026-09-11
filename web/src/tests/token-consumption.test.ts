import { describe, it, expect, vi, beforeEach, afterAll } from "vitest";
import bcrypt from "bcrypt";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));

import { action as resetPasswordAction } from "../routes/api/auth/reset-password.js";
import { loader as verifyEmailLoader } from "../routes/api/auth/verify-email/[token].js";
import { getDb } from "../lib/api/db.js";

// Token-consumption routes must be single-shot: the password write / email
// verification, the token clear and the revocation all live in ONE
// conditional UPDATE keyed on the capability, so concurrent requests see
// exactly one winner and replays get a 400.

function postRequest(body: unknown): Request {
  return new Request("http://localhost/api/auth/reset-password", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

// Simulates the single-consumption semantics of the conditional UPDATE:
// the first matching consume() returns a row, every later one zero rows.
function singleConsumptionDb() {
  const updates: Array<Record<string, unknown>> = [];
  let consumed = false;
  const consume = (patch: Record<string, unknown>) => ({
    where: () => ({
      returning: async () => {
        if (consumed) return [];
        consumed = true;
        updates.push(patch);
        return [{ id: "u1" }];
      },
    }),
  });
  return {
    updates,
    wasConsumed: () => consumed,
    db: {
      update: () => ({
        set: (patch: Record<string, unknown>) => consume(patch),
      }),
    },
  };
}

beforeEach(() => {
  vi.mocked(getDb).mockReset();
  process.env.BCRYPT_ROUNDS = "4";
});

afterAll(() => {
  process.env.BCRYPT_ROUNDS = "10";
});

describe("POST /api/auth/reset-password", () => {
  it("consumes the token exactly once across concurrent requests (one 200, one 400)", async () => {
    const { db, updates } = singleConsumptionDb();
    vi.mocked(getDb).mockResolvedValue(db as never);

    const body = { token: "reset-token-abc", password: "new-password-123" };
    const [first, second] = await Promise.all([
      resetPasswordAction({ request: postRequest(body) }),
      resetPasswordAction({ request: postRequest(body) }),
    ]);

    expect([first.status, second.status].sort()).toEqual([200, 400]);
    expect(updates).toHaveLength(1);
    const patch = updates[0] as { passwordHash?: string; tokenVersion?: unknown; passwordResetToken?: null };
    expect(await bcrypt.compare("new-password-123", patch.passwordHash!)).toBe(true);
    expect("tokenVersion" in patch).toBe(true);
    expect(patch.passwordResetToken).toBeNull();
  });

  it("returns 400 when no row matches the token", async () => {
    const { db } = singleConsumptionDb();
    vi.mocked(getDb).mockResolvedValue({
      ...db,
      update: () => ({
        set: (patch: Record<string, unknown>) => ({
          where: () => ({ returning: async () => { void patch; return []; } }),
        }),
      }),
    } as never);

    const response = await resetPasswordAction({
      request: postRequest({ token: "wrong-token", password: "new-password-123" }),
    });

    expect(response.status).toBe(400);
  });
});

async function thrownResponse(promise: Promise<unknown>): Promise<Response> {
  try {
    await promise;
  } catch (error) {
    return error as Response;
  }
  throw new Error("expected loader to throw its Response");
}

describe("GET /api/auth/verify-email/:token", () => {
  it("verifies once; a replayed token returns 400", async () => {
    const { db, updates } = singleConsumptionDb();
    vi.mocked(getDb).mockResolvedValue(db as never);

    const first = await thrownResponse(verifyEmailLoader({ params: { token: "verify-token-xyz" } }));
    const second = await thrownResponse(verifyEmailLoader({ params: { token: "verify-token-xyz" } }));

    expect(first.status).toBe(200);
    expect(second.status).toBe(400);
    expect(updates).toHaveLength(1);
    expect(updates[0].emailVerified).toBe(true);
    expect(updates[0].emailVerificationToken).toBeNull();
  });
});
