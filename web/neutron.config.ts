import { defineConfig } from "@neutron-build/core";

export default defineConfig({
  runtime: "preact",
  worker: {
    entry: "src/worker.ts",
  },
});
