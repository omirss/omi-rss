import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));
vi.mock("../data/runtime.js", () => ({
  getDataRuntime: vi.fn(async () => ({ queue: { add: vi.fn() } })),
}));

import { action } from "../routes/api/users/me.js";
import { getDb } from "../lib/api/db.js";
import { getDataRuntime } from "../data/runtime.js";

// PATCH /api/users/me with an email: (re)starts verification — email set,
// emailVerified cleared, fresh token, verification email queued. Without a
// usable email the account's email is left untouched (no email patch keys,
// no job) so unconditional form submits cannot re-trigger verification.

function patchRequest(body: Record<string, unknown>): Request {
  return new Request("http://localhost/api/users/me", {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

function fakeDb(selectResults: unknown[]) {
  let selectCall = 0;
  let setPatch: Record<string, unknown> | undefined;
  const select = () => {
    const rows = selectResults[Math.min(selectCall, selectResults.length - 1)] as unknown[];
    selectCall++;
    const q: Record<string, unknown> = {
      then: (onFulfilled: (value: unknown) => unknown, onRejected: (reason: unknown) => unknown) =>
        Promise.resolve(rows).then(onFulfilled, onRejected),
    };
    for (const method of ["from", "where", "limit"]) {
      q[method] = () => q;
    }
    return q as never;
  };
  const db = {
    select,
    update: () => ({
      set: (patch: Record<string, unknown>) => {
        setPatch = patch;
        return {
          where: () => ({
            returning: async () => [
              {
                id: "u1",
                email: "email" in patch && patch.email ? (patch.email as string) : "kept@test.local",
                username: "user",
              },
            ],
          }),
        };
      },
    }),
  };
  return { db, getSetPatch: () => setPatch };
}

const context = { user: { id: "u1" } };

beforeEach(() => {
  vi.mocked(getDb).mockReset();
  vi.mocked(getDataRuntime).mockReset();
  delete process.env.FRONTEND_URL;
  process.env.PORT = "3910";
});

describe("PATCH /api/users/me email handling", () => {
  it("setting an email resets verification and queues the verification email", async () => {
    const queueAdd = vi.fn();
    vi.mocked(getDataRuntime).mockImplementation(async () => ({ queue: { add: queueAdd } } as never));
    const { db, getSetPatch } = fakeDb([[]]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: patchRequest({ email: "new-address@test.local" }),
      context,
    });

    expect(response.status).toBe(200);
    const patch = getSetPatch()!;
    expect(patch.email).toBe("new-address@test.local");
    expect(patch.emailVerified).toBe(false);
    expect(patch.emailVerificationToken).toMatch(/^[0-9a-f]{64}$/);
    expect(queueAdd).toHaveBeenCalledTimes(1);
    const [jobName, payload] = queueAdd.mock.calls[0] as [string, { email: string; data: { verificationUrl: string } }];
    expect(jobName).toBe("notification.send-email");
    expect(payload.email).toBe("new-address@test.local");
    expect(payload.data.verificationUrl).toMatch(
      /^http:\/\/localhost:3910\/verify-email\?token=[0-9a-f]{64}$/
    );
  });

  it("conflicts with 409 when the email belongs to another account", async () => {
    const queueAdd = vi.fn();
    vi.mocked(getDataRuntime).mockImplementation(async () => ({ queue: { add: queueAdd } } as never));
    const { db, getSetPatch } = fakeDb([[{ id: "u2", email: "taken@test.local" }]]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: patchRequest({ email: "taken@test.local" }),
      context,
    });

    expect(response.status).toBe(409);
    const body = (await response.json()) as { error: string };
    expect(body.error).toBe("Email already in use");
    expect(getSetPatch()).toBeUndefined();
    expect(queueAdd).not.toHaveBeenCalled();
  });

  it("absent, null and empty-string email leave the account's email untouched", async () => {
    for (const email of [undefined, null, ""]) {
      const queueAdd = vi.fn();
      vi.mocked(getDataRuntime).mockImplementation(async () => ({ queue: { add: queueAdd } } as never));
      const { db, getSetPatch } = fakeDb([]);
      vi.mocked(getDb).mockResolvedValue(db as never);

      const response = await action({
        request: patchRequest({ email, firstName: "Test" }),
        context,
      });

      expect(response.status).toBe(200);
      const patch = getSetPatch()!;
      expect("email" in patch && patch.email !== undefined).toBe(false);
      expect("emailVerified" in patch).toBe(false);
      expect("emailVerificationToken" in patch).toBe(false);
      expect(queueAdd).not.toHaveBeenCalled();
    }
  });
});
