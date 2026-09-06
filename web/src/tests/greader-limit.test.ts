import { describe, it, expect, vi, beforeEach } from "vitest";
import { RateLimiterRes } from "rate-limiter-flexible";

const consume = vi.fn();

vi.mock("rate-limiter-flexible", () => {
  // A local class so both this file and limit.ts see the SAME constructor
  // for instanceof checks.
  class RateLimiterResMock {
    msBeforeNext = 0;
    constructor(msBeforeNext = 0) {
      this.msBeforeNext = msBeforeNext;
    }
  }
  return {
    RateLimiterRes: RateLimiterResMock,
    RateLimiterRedis: vi.fn().mockImplementation(() => ({ consume })),
  };
});

vi.mock("ioredis", () => ({ default: vi.fn().mockImplementation(() => ({ on: vi.fn() })) }));

import { consumeGreaderRateLimit } from "../lib/greader/limit.js";
import { AppError } from "../lib/api/errors.js";

// The greader-specific per-user bucket (600/15min, key omiweb_greader_limit):
// 429 as AppError when the budget is spent; fail-open with a warning when
// Redis is unavailable (mirrors consumeUserRateLimit; only the shared auth
// limiter is mandated fail-closed, and ClientLogin uses that one).

beforeEach(() => {
  consume.mockReset();
});

describe("consumeGreaderRateLimit", () => {
  it("passes when the budget allows", async () => {
    consume.mockResolvedValue(undefined);
    await expect(consumeGreaderRateLimit("u1")).resolves.toBeUndefined();
    expect(consume).toHaveBeenCalledWith("u1");
  });

  it("throws a 429 AppError when the bucket is spent", async () => {
    consume.mockRejectedValue(new RateLimiterRes(0, 0, 0));
    const error = await consumeGreaderRateLimit("u1").catch((e: unknown) => e);
    expect(error).toBeInstanceOf(AppError);
    expect((error as AppError).statusCode).toBe(429);
  });

  it("fails open on infrastructure errors", async () => {
    consume.mockRejectedValue(new Error("connection refused"));
    await expect(consumeGreaderRateLimit("u1")).resolves.toBeUndefined();
  });
});
