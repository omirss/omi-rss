// Tests for extension/js/feed-parser.js — body cap/timeout in fetchFeed,
// per-item date fallback, and text-mode Atom link handling. Plain
// `node --test`, no deps (node has no DOMParser, so the text parser is the
// exercised path).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { feedParser } = require('../js/feed-parser.js');

const FEED_XML = '<?xml version="1.0"?><rss version="2.0"><channel><title>t</title></channel></rss>';

function streamResponse(chunks) {
  let i = 0;
  const stream = new ReadableStream({
    pull(controller) {
      if (i < chunks.length) {
        controller.enqueue(chunks[i++]);
      }
      // Never completes: simulates a stalled body.
    }
  });
  return new Response(stream, { status: 200, headers: { 'content-type': 'text/xml' } });
}

// Like a real fetch body: the stream errors when the request's abort
// signal fires, so a stalled body rejects instead of hanging forever.
function stallableResponse(init, chunk) {
  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(chunk);
      init.signal.addEventListener('abort', () => {
        controller.error(new DOMException('Aborted', 'AbortError'));
      });
    }
  });
  return new Response(stream, { status: 200, headers: { 'content-type': 'text/xml' } });
}

test('fetchFeed rejects when the body exceeds the 5 MiB cap', async () => {
  const originalFetch = globalThis.fetch;
  const megabyte = new Uint8Array(1024 * 1024);
  globalThis.fetch = async () => streamResponse([megabyte, megabyte, megabyte, megabyte, megabyte, megabyte]);

  try {
    await assert.rejects(() => feedParser.fetchFeed('https://x.example/feed'), /exceeded/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('fetchFeed applies the timeout to the body read, not just the headers', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (_url, init) => stallableResponse(init, new TextEncoder().encode('<rss'));

  try {
    await assert.rejects(
      () => feedParser.fetchFeed('https://x.example/feed', { timeout: 50 }),
      /timed out/
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('one invalid pubDate falls back to arrival time without failing the feed', () => {
  const feed = {
    url: 'https://x.example/feed',
    title: 'T',
    items: [
      { title: 'one', link: 'https://x.example/1', pubDate: '2026-01-01T00:00:00Z' },
      { title: 'two', link: 'https://x.example/2', pubDate: 'not-a-date' },
      { title: 'three', link: 'https://x.example/3' }
    ]
  };

  const before = Date.now();
  const enhanced = feedParser.validateAndEnhanceFeed(feed, feed.url);
  const after = Date.now();

  assert.equal(enhanced.items.length, 3);
  const byTitle = Object.fromEntries(enhanced.items.map(item => [item.title, item]));
  assert.equal(byTitle.one.publishedAt, '2026-01-01T00:00:00.000Z');
  const fallback = new Date(byTitle.two.publishedAt).getTime();
  assert.ok(fallback >= before - 1 && fallback <= after + 1, 'fallback is arrival time');
  assert.ok(Number.isFinite(new Date(byTitle.three.publishedAt).getTime()));
});

test('text-mode Atom entries prefer the alternate link over a preceding self link', () => {
  const xml = `<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Feed</title>
  <link rel="self" href="https://x.example/feed.atom"/>
  <link href="https://x.example/" />
  <entry>
    <id>tag:x,2026:1</id>
    <title>Entry</title>
    <link rel="self" href="https://x.example/entries/1.atom"/>
    <link href="https://x.example/posts/1" />
    <summary>s</summary>
  </entry>
</feed>`;

  const feed = feedParser.parseXMLFeedText(xml, 'https://x.example/feed.atom');
  // A missing rel means alternate (RFC 4287): the self link must not win.
  assert.equal(feed.siteUrl, 'https://x.example/');
  assert.equal(feed.items[0].link, 'https://x.example/posts/1');
});

test('text-mode Atom guid falls back to the alternate link', () => {
  const xml = `<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Feed</title>
  <entry>
    <title>Entry</title>
    <link rel="self" href="https://x.example/e.atom"/>
    <link href="/rel" />
  </entry>
</feed>`;

  const feed = feedParser.parseXMLFeedText(xml, 'https://x.example/feed');
  assert.equal(feed.items[0].guid, 'https://x.example/rel');
  assert.equal(feed.items[0].link, 'https://x.example/rel');
});
