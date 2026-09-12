// Per-host outbound fetch semaphore (max 1 in-flight per hostname) shared by
// every outbound fetch in the worker process — feed refreshes, article
// extraction and page-feed polls alike — so concurrent queues can never hit
// one origin in parallel (ban-risk control; spike Q3).

const gates = new Map<string, Promise<unknown>>();

function hostKey(url: string): string {
  try {
    return new URL(url).hostname.toLowerCase();
  } catch {
    return url;
  }
}

// Serializes fn against every other withHostGate call for the same hostname;
// different hostnames run in parallel. The chain tail never rejects so one
// failing fetch cannot poison the host's queue. Completed tails are removed
// from the map (only when no newer request chained onto them), so the gate
// map does not grow monotonically with every hostname ever seen.
export function withHostGate<T>(url: string, fn: () => Promise<T>): Promise<T> {
  const key = hostKey(url);
  const tail = gates.get(key) ?? Promise.resolve();
  const result = tail.then(fn, fn);
  const next = result.then(
    () => undefined,
    () => undefined,
  );
  gates.set(key, next);
  void next.then(() => {
    if (gates.get(key) === next) {
      gates.delete(key);
    }
  });
  return result;
}

export function resetHostGates(): void {
  gates.clear();
}

export function hostGateCount(): number {
  return gates.size;
}
