import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ execute: vi.fn(), ping: vi.fn() }));
vi.mock("../data/runtime.js", () => ({
  getDataRuntime: vi.fn(async () => ({ database: { db: { execute: mocks.execute } } })),
}));
vi.mock("../lib/api/rate-limit.js", () => ({
  waitForLimiterRedis: vi.fn(async () => ({ ping: mocks.ping })),
}));

import { healthMiddleware } from "../lib/health.server.js";

function ready() {
  return healthMiddleware(new Request("http://localhost/ready"), {}, async () => new Response(null, { status: 404 }));
}

beforeEach(() => {
  vi.resetModules();
  vi.useFakeTimers();
  mocks.execute.mockReset().mockResolvedValue([]);
  mocks.ping.mockReset().mockResolvedValue("PONG");
});
afterEach(() => vi.useRealTimers());

describe("required readiness dependencies", () => {
  it("checks PostgreSQL and Redis", async () => {
    expect((await ready()).status).toBe(200);
    expect(mocks.execute).toHaveBeenCalledOnce();
    expect(mocks.ping).toHaveBeenCalledOnce();
    expect(vi.getTimerCount()).toBe(0);
  });
  it.each(["execute", "ping"] as const)("fails when %s rejects", async (dependency) => {
    mocks[dependency].mockRejectedValue(new Error("dependency down"));
    const response = await ready();
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ status: "not-ready" });
    expect(vi.getTimerCount()).toBe(0);
  });
  it.each(["execute", "ping"] as const)("bounds a hung %s", async (dependency) => {
    mocks[dependency].mockReturnValue(new Promise(() => {}));
    const response = ready();
    await vi.advanceTimersByTimeAsync(2500);
    expect((await response).status).toBe(503);
    expect(vi.getTimerCount()).toBe(0);
  });
});
