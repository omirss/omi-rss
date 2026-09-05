import { healthMiddleware } from "../lib/health.server.js";

export const config = { mode: "app" };

export const middleware = healthMiddleware;

export default function ReadyRoute() {
  return <main>GET /ready</main>;
}
