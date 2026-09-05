import { sql } from "drizzle-orm";
import type { PostgresJsDatabase } from "drizzle-orm/postgres-js";
import { createHealthcheckMiddleware } from "@neutron-build/ops";
import { getDataRuntime } from "../data/runtime.js";

async function ready(): Promise<boolean> {
  const runtime = await getDataRuntime();
  const db = runtime.database.db as PostgresJsDatabase<Record<string, never>>;
  await db.execute(sql`select 1`);
  return true;
}

export const healthMiddleware = createHealthcheckMiddleware({
  service: "omi-rss-web",
  healthPath: "/health",
  readyPath: "/ready",
  ready,
});
