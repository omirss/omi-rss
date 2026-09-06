import { describe, it, expect, vi, beforeEach, beforeAll, afterAll } from "vitest";

vi.mock("../lib/api/db.js", () => ({ getDb: vi.fn() }));
vi.mock("../data/runtime.js", () => ({
  getDataRuntime: vi.fn(async () => ({ queue: { add: vi.fn() } })),
}));
vi.mock("../lib/api/rate-limit.js", () => ({
  authRateLimitKey: vi.fn(() => null),
  consumeAuthRateLimit: vi.fn(),
  consumeAnonAuthRateLimit: vi.fn(),
}));

import { action } from "../routes/api/auth/register.js";
import { getDb } from "../lib/api/db.js";
import { getDataRuntime } from "../data/runtime.js";

// ALLOW_REGISTRATION gate: "false" closes sign-ups only once at least one
// user exists — an empty instance always allows the bootstrap registration.
// Default (unset or any other value) is open. Email is optional: absent,
// null and "" all register a username-only account with no verification
// flow.

function registerRequest(body: Record<string, unknown> = {}): Request {
  return new Request("http://localhost/api/auth/register", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email: "new-user@example.com",
      username: "new-user",
      password: "a-long-password",
      ...body,
    }),
  });
}

// The action runs up to two selects: the gate's users count (first) and the
// existing-email/username check (second, skipped on 403). selectResults
// supplies them in call order.
function fakeDb(selectResults: unknown[]) {
  const calls: unknown[][] = [];
  const inserts: Record<string, unknown>[] = [];
  const select = () => {
    const rows = selectResults[Math.min(calls.length, selectResults.length - 1)] as unknown[];
    calls.push(rows);
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
    insert: () => ({
      values: (value: Record<string, unknown>) => {
        inserts.push(value);
        return {
          returning: async () => [
            { id: "u-new", email: value.email ?? null, username: value.username },
          ],
        };
      },
    }),
  };
  return { db, calls, inserts };
}

beforeAll(() => {
  process.env.JWT_SECRET = "test-secret";
  process.env.BCRYPT_ROUNDS = "4";
});

beforeEach(() => {
  vi.mocked(getDb).mockReset();
  vi.mocked(getDataRuntime).mockReset();
  vi.mocked(getDataRuntime).mockImplementation(async () => ({ queue: { add: vi.fn() } } as never));
  delete process.env.ALLOW_REGISTRATION;
});

afterAll(() => {
  delete process.env.ALLOW_REGISTRATION;
  process.env.BCRYPT_ROUNDS = "10";
});

describe("ALLOW_REGISTRATION gate on POST /api/auth/register", () => {
  it("returns 403 when closed and at least one user exists", async () => {
    process.env.ALLOW_REGISTRATION = "false";
    const { db, calls } = fakeDb([[{ value: 1 }], []]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({ request: registerRequest() });

    expect(response.status).toBe(403);
    const body = (await response.json()) as { error: string };
    expect(body.error).toBe("Registration is closed");
    // Thrown before the existing-account probe: only the count select ran.
    expect(calls).toHaveLength(1);
  });

  it("returns 201 when closed but the instance is empty (bootstrap)", async () => {
    process.env.ALLOW_REGISTRATION = "false";
    const { db } = fakeDb([[{ value: 0 }], []]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({ request: registerRequest() });

    expect(response.status).toBe(201);
  });

  it("returns 201 when open (unset) even with existing users", async () => {
    const { db } = fakeDb([[]]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({ request: registerRequest() });

    expect(response.status).toBe(201);
  });
});

describe("optional email on POST /api/auth/register", () => {
  it("registers without email: null column, no verification token, no email job", async () => {
    const queueAdd = vi.fn();
    vi.mocked(getDataRuntime).mockImplementation(async () => ({ queue: { add: queueAdd } } as never));
    const { db, inserts } = fakeDb([[]]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: registerRequest({ email: undefined, username: "no-email-user" }),
    });

    expect(response.status).toBe(201);
    expect(inserts[0].email).toBeNull();
    expect(inserts[0].emailVerificationToken).toBeNull();
    expect(queueAdd).not.toHaveBeenCalled();
    const body = (await response.json()) as { user: { email: string | null } };
    expect(body.user.email).toBeNull();
  });

  it("treats an empty-string email as absent", async () => {
    const queueAdd = vi.fn();
    vi.mocked(getDataRuntime).mockImplementation(async () => ({ queue: { add: queueAdd } } as never));
    const { db, inserts } = fakeDb([[]]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({ request: registerRequest({ email: "" }) });

    expect(response.status).toBe(201);
    expect(inserts[0].email).toBeNull();
    expect(queueAdd).not.toHaveBeenCalled();
  });

  it("keeps the verification flow when an email is provided", async () => {
    const queueAdd = vi.fn();
    vi.mocked(getDataRuntime).mockImplementation(async () => ({ queue: { add: queueAdd } } as never));
    const { db, inserts } = fakeDb([[]]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({ request: registerRequest() });

    expect(response.status).toBe(201);
    expect(inserts[0].email).toBe("new-user@example.com");
    expect(typeof inserts[0].emailVerificationToken).toBe("string");
    expect(queueAdd).toHaveBeenCalledWith(
      "notification.send-email",
      expect.objectContaining({ email: "new-user@example.com" }),
    );
  });

  it("conflicts with 409 on a duplicate username", async () => {
    // Gate unset: only the conflict select runs.
    const { db, inserts } = fakeDb([[{ id: "u-existing", username: "new-user" }]]);
    vi.mocked(getDb).mockResolvedValue(db as never);

    const response = await action({
      request: registerRequest({ email: undefined, username: "new-user" }),
    });

    expect(response.status).toBe(409);
    expect(inserts).toHaveLength(0);
  });
});
