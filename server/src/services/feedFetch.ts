import { logger } from '../utils/logger';

const FEED_USER_AGENT = 'omi-rss/0.2 (+https://omirss.com)';
const FEED_TIMEOUT_MS = 15000;
const FEED_RETRY_DELAYS_MS = [1000, 3000];
const FEED_RATE_LIMIT_RETRY_DELAY_MS = 10000;

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

interface FeedHttpResponse {
  status: number;
  body: string | null;
}

async function fetchFeedOnce(url: string): Promise<FeedHttpResponse> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FEED_TIMEOUT_MS);

  try {
    const response = await fetch(url, {
      headers: {
        'User-Agent': FEED_USER_AGENT,
        Accept: 'application/rss+xml, application/atom+xml, application/xml, text/xml, */*',
      },
      signal: controller.signal,
    });

    const body = response.ok ? await response.text() : null;
    return { status: response.status, body };
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      throw new Error(`Feed fetch timed out after ${FEED_TIMEOUT_MS}ms: ${url}`);
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

export async function fetchFeedXml(url: string): Promise<string> {
  const maxAttempts = FEED_RETRY_DELAYS_MS.length + 1;
  let retryDelay = 0;
  let lastError: unknown = new Error(`Failed to fetch feed: ${url}`);

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    if (retryDelay > 0) {
      await sleep(retryDelay);
    }

    try {
      const { status, body } = await fetchFeedOnce(url);

      if (body !== null) {
        return body;
      }

      lastError = new Error(`HTTP ${status} fetching feed: ${url}`);
      retryDelay = status === 429 ? FEED_RATE_LIMIT_RETRY_DELAY_MS : FEED_RETRY_DELAYS_MS[attempt - 1];
    } catch (error) {
      lastError = error;
      retryDelay = FEED_RETRY_DELAYS_MS[attempt - 1];
    }

    if (attempt < maxAttempts) {
      logger.warn(
        `Feed fetch attempt ${attempt}/${maxAttempts} failed for ${url}: ${
          lastError instanceof Error ? lastError.message : String(lastError)
        }`,
      );
    }
  }

  throw lastError instanceof Error ? lastError : new Error(`Failed to fetch feed: ${url}`);
}
