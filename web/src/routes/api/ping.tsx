export const config = { mode: "app" };

export async function loader() {
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
