import { handleLoader } from "../lib/api/errors.js";

export const config = { mode: "app" };

// The extension's Register button links here; the login page owns the
// register tab, so bounce to it (302: the target may change with the
// registration gate, so no permanent 301).
export async function loader(): Promise<never> {
  return handleLoader(async () =>
    new Response(null, {
      status: 302,
      headers: { Location: "/login?tab=register" },
    }),
  );
}
