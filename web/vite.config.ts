import preact from "@preact/preset-vite";
import { neutronPlugin } from "@neutron-build/core/vite";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [preact(), neutronPlugin()],
});
