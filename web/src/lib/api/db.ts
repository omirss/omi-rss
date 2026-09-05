import type { PostgresJsDatabase } from "drizzle-orm/postgres-js";
import { getDataRuntime } from "../../data/runtime.js";
import * as schema from "../../data/db/schema.js";

export type Database = PostgresJsDatabase<typeof schema>;

export async function getDb(): Promise<Database> {
  const runtime = await getDataRuntime();
  return runtime.database.db as Database;
}
