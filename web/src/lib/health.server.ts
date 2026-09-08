import { sql } from "drizzle-orm";
import type { PostgresJsDatabase } from "drizzle-orm/postgres-js";
import { createHealthcheckMiddleware } from "@neutron-build/ops";
import { getDataRuntime } from "../data/runtime.js";
import { waitForLimiterRedis } from "./api/rate-limit.js";

async function ready(): Promise<boolean> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    await Promise.race([
      Promise.all([
        (async () => {
          const runtime = await getDataRuntime();
          const db = runtime.database.db as PostgresJsDatabase<Record<string, never>>;
          await db.execute(sql`select 1`);
        })(),
        (async () => { await (await waitForLimiterRedis()).ping(); })(),
      ]),
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error("Readiness timed out")), 2500);
      }),
    ]);
    return true;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

export const healthMiddleware = createHealthcheckMiddleware({
  service: "omi-rss-web",
  healthPath: "/health",
  readyPath: "/ready",
  ready,
});
