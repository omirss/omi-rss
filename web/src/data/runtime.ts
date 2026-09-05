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
    runtimePromise = createRuntime();
  }
  return runtimePromise;
}

async function createRuntime(): Promise<DataRuntime> {
  const database = await createDrizzleDatabase({ schema });
  const redisUrl = process.env.REDIS_URL || "redis://localhost:6380";

  const cache = await createRedisCacheClient({
    url: redisUrl,
    keyPrefix: "omiweb:cache:",
  });

  const sessions = await createRedisSessionStore({
    url: redisUrl,
    keyPrefix: "omiweb:",
    sessionPrefix: "session:",
    sessionTtlSec: 60 * 60 * 24 * 7,
  });

  const queue = await createBullMqQueueDriver({
    url: redisUrl,
    queueName: QUEUE_NAME,
    prefix: QUEUE_PREFIX,
    concurrency: 4,
  });

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
    close: async () => {
      await queue.close();
      await sessions.close();
      await cache.close();
      await database.close();
    },
  };
}
