import { createRequestContextMiddleware } from "@neutron-build/ops";
import { securityHeaders } from "./lib/api/security-headers.js";

// securityHeaders runs on every app-route request (webui, API, uploads) and
// applies the baseline header set; its module also runs the production
// JWT_SECRET boot gate at load time.
export const middleware = [createRequestContextMiddleware(), securityHeaders];

export default middleware;
