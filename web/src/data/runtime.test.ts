import { describe, it, expect, vi, beforeEach } from "vitest";

const creators = vi.hoisted(() => ({
  createDrizzleDatabase: vi.fn(),
  createRedisCacheClient: vi.fn(),
  createRedisSessionStore: vi.fn(),
  createBullMqQueueDriver: vi.fn(),
}));

vi.mock("@neutron-build/data", () => creators);

async function freshRuntime() {
  const { getDataRuntime } = await import("./runtime.js");
  return getDataRuntime;
}

describe("getDataRuntime poison cache", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.clearAllMocks();
  });

  it("clears the cached promise on rejection so the next call retries", async () => {
    creators.createDrizzleDatabase.mockRejectedValue(new Error("db down"));

    const getDataRuntime = await freshRuntime();
    await expect(getDataRuntime()).rejects.toThrow("db down");
    await expect(getDataRuntime()).rejects.toThrow("db down");

    expect(creators.createDrizzleDatabase).toHaveBeenCalledTimes(2);
  });

  it("caches the runtime between calls on success", async () => {
    creators.createDrizzleDatabase.mockResolvedValue({
      profile: { provider: "postgres" },
      close: vi.fn(),
    });
    creators.createRedisCacheClient.mockResolvedValue({ close: vi.fn() });
    creators.createRedisSessionStore.mockResolvedValue({ close: vi.fn() });
    creators.createBullMqQueueDriver.mockResolvedValue({ close: vi.fn() });

    const getDataRuntime = await freshRuntime();
    const a = await getDataRuntime();
    const b = await getDataRuntime();

    expect(a).toBe(b);
    expect(creators.createDrizzleDatabase).toHaveBeenCalledTimes(1);
  });

  it("closes already-created drivers when a later allocation fails", async () => {
    const dbClose = vi.fn();
    const cacheClose = vi.fn();
    creators.createDrizzleDatabase.mockResolvedValue({
      profile: { provider: "postgres" },
      close: dbClose,
    });
    creators.createRedisCacheClient.mockResolvedValue({ close: cacheClose });
    creators.createRedisSessionStore.mockRejectedValue(new Error("sessions down"));

    const getDataRuntime = await freshRuntime();
    await expect(getDataRuntime()).rejects.toThrow("sessions down");

    expect(dbClose).toHaveBeenCalledTimes(1);
    expect(cacheClose).toHaveBeenCalledTimes(1);
  });

  it("close() runs every closer even when one rejects", async () => {
    const closes = [vi.fn(), vi.fn(async () => { throw new Error("queue close failed"); }), vi.fn(), vi.fn()];
    creators.createDrizzleDatabase.mockResolvedValue({
      profile: { provider: "postgres" },
      close: closes[0],
    });
    creators.createRedisCacheClient.mockResolvedValue({ close: closes[1] });
    creators.createRedisSessionStore.mockResolvedValue({ close: closes[2] });
    creators.createBullMqQueueDriver.mockResolvedValue({ close: closes[3] });

    const getDataRuntime = await freshRuntime();
    const runtime = await getDataRuntime();

    await expect(runtime.close()).rejects.toThrow("queue close failed");

    for (const close of closes) {
      expect(close).toHaveBeenCalledTimes(1);
    }
  });
});
