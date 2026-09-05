import type { LoaderArgs } from "@neutron-build/core";

export const config = { mode: "static" };

export async function loader(_args: LoaderArgs) {
  return {
    name: "Omi RSS",
    status: "Neutron web scaffold",
  };
}

interface LoaderData {
  name: string;
  status: string;
}

export default function Home({ data }: { data: LoaderData }) {
  return (
    <div>
      <h1>{data?.name}</h1>
      <p>{data?.status}</p>
      <ul>
        <li>
          <a href="/health">/health</a> — liveness (neutron-ops)
        </li>
        <li>
          <a href="/ready">/ready</a> — readiness (Postgres ping)
        </li>
        <li>
          <a href="/api/ping">/api/ping</a> — sample API route (zod-validated POST)
        </li>
      </ul>
    </div>
  );
}
