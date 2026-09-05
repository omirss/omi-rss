import { apiRateLimit } from "../../lib/api/rate-limit.js";

export const config = { mode: "app" };

// Mirrors the Express server's app.use('/api/', rateLimiter): every request
// under /api consumes the global limiter budget before any route runs.
export const middleware = apiRateLimit;

export default function ApiLayout({ children }: { children: preact.ComponentChildren }) {
  return <>{children}</>;
}
