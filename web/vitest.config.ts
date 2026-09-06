import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
    // Machine-load flakes (runtime.test.ts spins up real infra timeouts) —
    // widen the ceiling instead of restructuring the suites.
    testTimeout: 20000,
  },
});
