/// <reference types="vite/client" />

declare module "virtual:neutron/routes" {
  export const routes: Parameters<
    typeof import("@neutron-build/core/client").registerRoutes
  >[0];
}
