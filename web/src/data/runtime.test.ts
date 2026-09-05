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
});
