import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { EventEmitter } from "node:events";

const mocks = vi.hoisted(() => ({ consume: vi.fn(), client: null as unknown }));
vi.mock("ioredis", () => ({ default: vi.fn(() => mocks.client) }));
vi.mock("rate-limiter-flexible", () => ({
  RateLimiterRedis: vi.fn(() => ({ consume: mocks.consume })),
  RateLimiterRes: class {},
}));

let client: EventEmitter & { status: string };
beforeEach(() => {
  vi.resetModules();
  vi.useFakeTimers();
  vi.stubEnv("NODE_ENV", "production");
  client = Object.assign(new EventEmitter(), { status: "connecting" });
  mocks.client = client;
  mocks.consume.mockReset().mockResolvedValue(undefined);
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

describe("Redis limiter readiness", () => {
  it("waits for the cold connection before consuming simultaneous auth requests", async () => {
    const { consumeAuthRateLimit } = await import("../lib/api/rate-limit.js");
    const requests = [consumeAuthRateLimit("one"), consumeAuthRateLimit("two")];
    expect(mocks.consume).not.toHaveBeenCalled();
    client.status = "ready";
    client.emit("ready");
    await Promise.all(requests);
    expect(mocks.consume.mock.calls).toEqual([["one"], ["two"]]);
    expect(client.listenerCount("ready")).toBe(0);
    expect(client.listenerCount("end")).toBe(0);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("fails closed after a bounded wait and removes listeners", async () => {
    const { consumeAuthRateLimit } = await import("../lib/api/rate-limit.js");
    const assertion = expect(consumeAuthRateLimit("one")).rejects.toMatchObject({ statusCode: 503 });
    await vi.advanceTimersByTimeAsync(2000);
    await assertion;
    expect(mocks.consume).not.toHaveBeenCalled();
    expect(client.listenerCount("ready")).toBe(0);
    expect(client.listenerCount("end")).toBe(0);
  });

  it("fails closed if a ready connection fails during consumption", async () => {
    client.status = "ready";
    mocks.consume.mockRejectedValue(new Error("connection lost"));
    const { consumeAuthRateLimit } = await import("../lib/api/rate-limit.js");
    await expect(consumeAuthRateLimit("one")).rejects.toMatchObject({ statusCode: 503 });
  });
});
