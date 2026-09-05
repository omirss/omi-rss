import { describe, it, expect, beforeEach } from "vitest";
import { withHostGate, resetHostGates } from "./host-gate.js";

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

// Per-host semaphore: max 1 in-flight fetch per hostname across all queues
// in the worker process; different hosts run in parallel (spike Q3).

interface Timeline {
  events: string[];
  work(host: string, ms: number): Promise<string>;
}

function timeline(): Timeline {
  const events: string[] = [];
  return {
    events,
    work(host: string, ms: number) {
      return withHostGate(`https://${host}/page`, async () => {
        events.push(`start:${host}`);
        await sleep(ms);
        events.push(`end:${host}`);
        return host;
      });
    },
  };
}

describe("withHostGate", () => {
  beforeEach(() => {
    resetHostGates();
  });

  it("serializes concurrent fetches to the same host", async () => {
    const t = timeline();
    await Promise.all([t.work("same.example", 60), t.work("same.example", 60)]);

    expect(t.events).toEqual(["start:same.example", "end:same.example", "start:same.example", "end:same.example"]);
  });

  it("runs fetches to different hosts in parallel", async () => {
    const t = timeline();
    await Promise.all([t.work("a.example", 80), t.work("b.example", 80)]);

    const starts = t.events.filter((e) => e.startsWith("start:"));
    expect(starts).toHaveLength(2);
    // Both starts happen before either end — no cross-host serialization.
    expect(t.events.indexOf("start:a.example")).toBeLessThan(t.events.indexOf("end:b.example"));
    expect(t.events.indexOf("start:b.example")).toBeLessThan(t.events.indexOf("end:a.example"));
  });

  it("keeps serving after a gated fetch rejects", async () => {
    const t = timeline();
    const failing = withHostGate("https://err.example/x", async () => {
      t.events.push("start:err.example");
      await sleep(30);
      throw new Error("boom");
    });
    await expect(failing).rejects.toThrow("boom");
    await t.work("err.example", 10);
    expect(t.events).toEqual(["start:err.example", "start:err.example", "end:err.example"]);
  });
});
