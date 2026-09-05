import { handle, handleLoader, jsonResponse } from "../../lib/api/errors.js";

export const config = { mode: "app" };

// Mirrors the Express catch-all 404 handler for unknown /api routes.
function notFound(method: string, pathname: string): Response {
  return jsonResponse(
    {
      error: "Not Found",
      message: `Cannot ${method} ${pathname}`,
      timestamp: new Date().toISOString(),
    },
    404
  );
}

export async function loader({ request }: { request: Request }) {
  const url = new URL(request.url);
  return handleLoader(async () => notFound(request.method, url.pathname));
}

export async function action({ request }: { request: Request }) {
  const url = new URL(request.url);
  return handle(async () => notFound(request.method, url.pathname));
}
