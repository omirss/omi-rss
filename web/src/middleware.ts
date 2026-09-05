import { createRequestContextMiddleware } from "@neutron-build/ops";

export const middleware = [createRequestContextMiddleware()];

export default middleware;
