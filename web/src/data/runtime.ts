import {
  createBullMqQueueDriver,
  createDrizzleDatabase,
  createRedisCacheClient,
  createRedisSessionStore,
  type CacheClient,
  type DrizzleDatabase,
  type QueueDriver,
  type SessionStore,
} from "@neutron-build/data";
import * as schema from "./db/schema.js";

export const QUEUE_PREFIX = "omiweb";
export const QUEUE_NAME = "omiweb-feed-refresh";

export interface DataRuntime {
  drivers: {
    database: string;
    cache: string;
    session: string;
    queue: string;
  };
  database: DrizzleDatabase;
  cache: CacheClient;
  sessions: SessionStore;
  queue: QueueDriver;
  close(): Promise<void>;
}

let runtimePromise: Promise<DataRuntime> | null = null;

export function getDataRuntime(): Promise<DataRuntime> {
  if (!runtimePromise) {
    runtimePromise = createRuntime().catch((error) => {
      // Don't poison the cache with a rejected promise — clear it so the
      // next call retries instead of rethrowing the stale failure forever.
      runtimePromise = null;
      throw error;
    });
  }
  return runtimePromise;
}

async function createRuntime(): Promise<DataRuntime> {
  // Every successfully allocated driver registers its closer; a later
  // allocation failure (or shutdown) runs ALL of them in reverse creation
  // order, isolated — one rejecting close never skips the rest.
  const closers: Array<() => Promise<void> | void> = [];
  const closeAll = async (): Promise<void> => {
    const errors: unknown[] = [];
    for (const close of [...closers].reverse()) {
      try {
        await close();
      } catch (error) {
        errors.push(error);
      }
    }
    if (errors.length > 0) {
      throw errors[0];
    }
  };

  try {
    const database = await createDrizzleDatabase({ schema });
    closers.push(() => database.close());

    const redisUrl = process.env.REDIS_URL || "redis://localhost:6380";

    const cache = await createRedisCacheClient({
      url: redisUrl,
      keyPrefix: "omiweb:cache:",
    });
    closers.push(() => cache.close());

    const sessions = await createRedisSessionStore({
      url: redisUrl,
      keyPrefix: "omiweb:",
      sessionPrefix: "session:",
      sessionTtlSec: 60 * 60 * 24 * 7,
    });
    closers.push(() => sessions.close());

    const queue = await createBullMqQueueDriver({
      url: redisUrl,
      queueName: QUEUE_NAME,
      prefix: QUEUE_PREFIX,
      concurrency: 4,
    });
    closers.push(() => queue.close());

    return {
      drivers: {
        database: `drizzle:${database.profile.provider}`,
        cache: "redis-compatible",
        session: "redis-compatible",
        queue: "bullmq",
      },
      database,
      cache,
      sessions,
      queue,
      close: closeAll,
    };
  } catch (error) {
    await closeAll().catch((closeError) => {
      console.error("Runtime cleanup after failed initialization failed:", closeError);
    });
    throw error;
  }
}
