import { Queue } from "bullmq";
import { getDataRuntime, QUEUE_NAME, QUEUE_PREFIX } from "./data/runtime.js";

interface WorkerContext {
  mode: string;
  args: string[];
  signal: AbortSignal;
  log: (message: string) => void;
}

const FEED_REFRESH_JOB = "feed.refresh";
const FEED_REFRESH_CRON = "*/5 * * * *";

export async function run(context: WorkerContext): Promise<() => Promise<void>> {
  const runtime = await getDataRuntime();

  await runtime.queue.process(FEED_REFRESH_JOB, async (job) => {
    context.log(`feed refresh stub job=${job.name} id=${job.id}`);
  });

  // neutron-data's QueueDriver has no repeatable-job API, so the cron
  // registration goes straight to BullMQ on the same prefixed queue. The
  // neutron-data worker above still consumes the jobs it produces.
  const scheduler = new Queue(QUEUE_NAME, {
    prefix: QUEUE_PREFIX,
    connection: { url: process.env.REDIS_URL || "redis://localhost:6380" },
  });
  await scheduler.add(FEED_REFRESH_JOB, {}, { repeat: { pattern: FEED_REFRESH_CRON } });
  context.log(
    `repeatable job registered name=${FEED_REFRESH_JOB} cron='${FEED_REFRESH_CRON}' queue=${QUEUE_PREFIX}:${QUEUE_NAME}`
  );

  context.log(
    `ready database=${runtime.drivers.database} queue=${runtime.drivers.queue} mode=${context.mode}`
  );

  return async () => {
    await scheduler.close();
    await runtime.close();
    context.log("shutdown complete");
  };
}
