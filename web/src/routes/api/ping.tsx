import { z } from "zod";
import type { LoaderArgs } from "@neutron-build/core";

export const config = { mode: "app" };

const PingInput = z.object({
  name: z.string().min(1).max(100).optional(),
});

export async function loader(_args: LoaderArgs) {
  throw new Response(
    JSON.stringify({ ok: true, service: "omi-rss-web", time: new Date().toISOString() }),
    {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
    }
  );
}

export async function action({ request }: { request: Request }) {
  const raw = await request.text();
  let body: unknown = {};
  if (raw) {
    try {
      body = JSON.parse(raw);
    } catch {
      body = null;
    }
  }

  const parsed = PingInput.safeParse(body);
  if (!parsed.success) {
    return Response.json(
      {
        type: "https://neutron.dev/errors/validation",
        title: "Validation Failed",
        status: 422,
        detail: "Request body failed validation",
        errors: parsed.error.issues.map((issue) => ({
          field: issue.path.join(".") || "body",
          message: issue.message,
        })),
      },
      { status: 422, headers: { "Content-Type": "application/problem+json" } }
    );
  }

  const name = parsed.data.name;
  return Response.json({ ok: true, message: name ? `pong, ${name}` : "pong" });
}

export default function ApiPingRoute() {
  return <main>GET / POST /api/ping</main>;
}
