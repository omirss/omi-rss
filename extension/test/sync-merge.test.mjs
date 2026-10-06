// Tests for the pure SyncManager.mergeData (cross-profile file sync):
// per-feed GUID keys, name-path folder identity, flag unions and real
// settings timestamps. Plain `node --test`, no deps.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

// Stub enough of chrome for the module to load (constructor init only
// touches storage.local; the message listener registration is a no-op).
function makeChrome() {
  const storage = new Map();
  const area = {
    get: async (keys) => {
      const out = {};
      for (const key of Array.isArray(keys) ? keys : [keys]) {
        if (storage.has(key)) out[key] = storage.get(key);
      }
      return out;
    },
    set: async (obj) => {
      for (const [key, value] of Object.entries(obj)) storage.set(key, value);
    },
  };
  return {
    storage: { local: area, sync: area },
    runtime: {
      onMessage: { addListener() {} },
      sendMessage: async () => {}
    }
  };
}

globalThis.chrome = makeChrome();
const { SyncManager } = require('../js/sync-manager.js');

const merge = (local, remote) => SyncManager.prototype.mergeData.call(Object.create(SyncManager.prototype), local, remote);

const snapshot = (data, timestamp = 1000) => ({
  version: '1.0',
  deviceId: 'd',
  timestamp,
  data: {
    feeds: [], articles: [], settings: {}, readStatus: {}, savedArticles: [], folders: [],
    ...data
  }
});

test('same-GUID articles from different feeds both survive (guid uniqueness is per feed)', () => {
  const local = snapshot({
    feeds: [{ id: 1, url: 'https://a.example/feed', updatedAt: '2026-01-01' }],
    articles: [{ id: 10, feedId: 1, guid: 'shared', title: 'From A', updatedAt: '2026-01-01' }]
  });
  const remote = snapshot({
    feeds: [{ id: 99, url: 'https://b.example/feed', updatedAt: '2026-01-02' }],
    articles: [{ id: 900, feedId: 99, guid: 'shared', title: 'From B', updatedAt: '2026-01-02' }]
  });

  const merged = merge(local, remote);
  assert.equal(merged.data.articles.length, 2);
});

test('same feed, same guid: newer content wins, read/saved flags union', () => {
  const local = snapshot({
    feeds: [{ id: 1, url: 'https://a.example/feed', updatedAt: '2026-01-01' }],
    articles: [{ id: 10, feedId: 1, guid: 'g', title: 'Old title', isRead: true, isSaved: false, updatedAt: '2026-01-01' }]
  });
  const remote = snapshot({
    feeds: [{ id: 5, url: 'https://a.example/feed', updatedAt: '2026-01-02' }],
    articles: [{ id: 50, feedId: 5, guid: 'g', title: 'New title', isRead: false, isSaved: true, updatedAt: '2026-01-02' }]
  });

  const merged = merge(local, remote);
  assert.equal(merged.data.articles.length, 1);
  assert.equal(merged.data.articles[0].title, 'New title');
  assert.equal(merged.data.articles[0].isRead, true);
  assert.equal(merged.data.articles[0].isSaved, true);
});

test('folder identity is the name path: same-name folders in different branches both survive', () => {
  const local = snapshot({
    folders: [
      { id: 1, name: 'Tech', parentId: null },
      { id: 2, name: 'Deep', parentId: 1 }
    ]
  });
  const remote = snapshot({
    folders: [
      { id: 50, name: 'Tech', parentId: null },
      { id: 51, name: 'Deep', parentId: 50 },
      { id: 52, name: 'News', parentId: null }
    ]
  });

  const merged = merge(local, remote);
  // Both local folders stay (paths Tech and Tech/Deep match), the remote
  // Tech/Tech-Deep duplicates are dropped by path, News is new.
  assert.equal(merged.data.folders.filter(f => f.name === 'Tech').length, 1);
  assert.equal(merged.data.folders.filter(f => f.name === 'Deep').length, 1);
  assert.ok(merged.data.folders.some(f => f.name === 'News'));
});

test('saved pages dedupe by URL, not object identity', () => {
  const local = snapshot({ savedArticles: [{ id: 'a', url: 'https://x.example/1' }] });
  const remote = snapshot({ savedArticles: [{ id: 'b', url: 'https://x.example/1' }, { id: 'c', url: 'https://x.example/2' }] });

  const merged = merge(local, remote);
  assert.equal(merged.data.savedArticles.length, 2);
});

test('settings follow the real persisted timestamps (a fresh local export no longer auto-wins)', () => {
  const local = snapshot({ settings: { theme: 'dark' } }, 500);
  const remote = snapshot({ settings: { theme: 'light' } }, 900);

  const merged = merge(local, remote);
  assert.equal(merged.settingsFromRemote, true);
  assert.equal(merged.data.settings.theme, 'light');

  const mergedReverse = merge(
    snapshot({ settings: { theme: 'dark' } }, 900),
    snapshot({ settings: { theme: 'light' } }, 500)
  );
  assert.equal(mergedReverse.settingsFromRemote, false);
  assert.equal(mergedReverse.data.settings.theme, 'dark');
});

test('read status is a union of both sides', () => {
  const merged = merge(
    snapshot({ readStatus: { a: true } }),
    snapshot({ readStatus: { b: true } })
  );
  assert.deepEqual(merged.data.readStatus, { a: true, b: true });
});

test('R4-14: colliding cross-profile feed ids never re-attribute articles', () => {
  // Local feed id 1 is url A; REMOTE feed id 1 is a DIFFERENT feed (url
  // B). A single shared id->url map resolved local articles against
  // whichever side was inserted last, silently moving them to the
  // wrong feed.
  const local = snapshot({
    feeds: [{ id: 1, url: 'https://a.example/feed', updatedAt: '2026-01-01' }],
    articles: [{ id: 10, feedId: 1, guid: 'x', title: 'Belongs to A', updatedAt: '2026-01-01' }]
  });
  const remote = snapshot({
    feeds: [{ id: 1, url: 'https://b.example/feed', updatedAt: '2026-01-02' }],
    articles: [{ id: 20, feedId: 1, guid: 'y', title: 'Belongs to B', updatedAt: '2026-01-02' }]
  });

  const merged = merge(local, remote);
  assert.equal(merged.data.articles.length, 2);
  const articleA = merged.data.articles.find(a => a.guid === 'x');
  const articleB = merged.data.articles.find(a => a.guid === 'y');
  assert.equal(articleA._syncFeedUrl, 'https://a.example/feed');
  assert.equal(articleB._syncFeedUrl, 'https://b.example/feed');
});

test('R4-16: the winning feed patch carries the disabled flag', () => {
  const patch = SyncManager.feedApplyPatch(
    { title: 'T', description: 'D', siteUrl: 's', favicon: 'f', updateInterval: 30, disabled: true, folderId: null },
    new Map()
  );
  assert.equal(patch.disabled, true, 'a winning disable must apply');

  const enabled = SyncManager.feedApplyPatch(
    { title: 'T', siteUrl: 's', updateInterval: 30, disabled: false, folderId: 5 },
    new Map([[5, 50]])
  );
  assert.equal(enabled.disabled, false);
  assert.equal(enabled.folderId, 50, 'a winning folder move remaps to the local id');
});

test('R4-16: removing the folder on the winning row propagates as null', () => {
  // The winner has no folder; the patch must CLEAR the local folder,
  // not skip the key (skipping silently kept the old assignment).
  const patch = SyncManager.feedApplyPatch(
    { title: 'T', siteUrl: 's', updateInterval: 30, folderId: null },
    new Map([[7, 70]])
  );
  assert.ok('folderId' in patch);
  assert.equal(patch.folderId, null);

  // A folder reference that maps to nothing local leaves the local
  // assignment untouched rather than corrupting it.
  const unknown = SyncManager.feedApplyPatch(
    { title: 'T', siteUrl: 's', updateInterval: 30, folderId: 404 },
    new Map([[7, 70]])
  );
  assert.ok(!('folderId' in unknown));
});
