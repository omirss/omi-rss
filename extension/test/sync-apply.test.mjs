// Tests for SyncManager.applyMergedData — the APPLY half of the
// cross-profile file sync that had zero coverage before (only the pure
// merge phase was tested). Storage ids are per-profile auto-increment
// counters, so these fixtures use colliding ids on purpose: local id 1
// and remote id 1 must never resolve to the same local row.
// Plain `node --test`, no deps.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

// chrome stub with SEPARATE local and sync areas (the settings bug was
// exactly that production code read an area nothing writes).
function makeChrome() {
  const area = () => {
    const storage = new Map();
    return {
      _storage: storage,
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
  };
  return {
    storage: { local: area(), sync: area() },
    runtime: {
      onMessage: { addListener() {} },
      sendMessage: async () => {}
    }
  };
}

// In-memory stand-in for the real IndexedDB storageService with
// auto-increment ids per store, a unique url index on feeds and the
// unique (feedId, guid) semantics on articles — the parts the apply
// phase relies on.
function makeStorageService() {
  let nextFeedId = 1;
  let nextFolderId = 1;
  let nextArticleId = 1;
  const feeds = new Map();
  const folders = new Map();
  const articles = new Map();

  const feedByUrl = (url) => {
    for (const feed of feeds.values()) {
      if (feed.url === url) return feed;
    }
    return null;
  };
  const articleByFeedGuid = (feedId, guid) => {
    for (const article of articles.values()) {
      if (article.feedId === feedId && article.guid === guid) return article;
    }
    return null;
  };

  const service = {
    async ensureReady() {},
    async getAllFolders() {
      return Array.from(folders.values()).map(folder => ({ ...folder }));
    },
    async addFolder(name, parentId = null) {
      const folder = { id: nextFolderId++, name, parentId };
      folders.set(folder.id, folder);
      return { ...folder };
    },
    async getFeedByUrl(url) {
      const feed = feedByUrl(url);
      return feed ? { ...feed } : null;
    },
    async updateFeed(id, updates) {
      const feed = feeds.get(id);
      if (!feed) throw new Error('Feed not found');
      Object.assign(feed, updates);
      return { ...feed };
    },
    async addFeed(data) {
      const id = nextFeedId++;
      feeds.set(id, { ...data, id });
      return id;
    },
    async exportAllData() {
      return {
        feeds: Array.from(feeds.values()).map(f => ({ ...f })),
        articles: Array.from(articles.values()).map(a => ({ ...a })),
        folders: Array.from(folders.values()).map(f => ({ ...f }))
      };
    },
    // Read-only view for assertions.
    _feeds: feeds,
    _folders: folders,
    _articles: articles
  };

  // Minimal fake of the single-store readwrite transaction the article
  // import performs: (feedId, guid) index reads and id-keyed puts.
  // Request callbacks fire on a microtask, after the caller has
  // attached its handlers — matching IndexedDB's async dispatch.
  service.db = {
    transaction() {
      const queue = [];
      let finished = false;
      const tx = {
        objectStore: () => ({
          index: () => ({
            get: ([feedId, guid]) => {
              const found = articleByFeedGuid(feedId, guid);
              const request = {
                result: found ? { ...found } : undefined,
                onsuccess: null,
                onerror: null
              };
              queue.push(() => request.onsuccess && request.onsuccess({ target: request }));
              return request;
            }
          }),
          put: (row) => {
            const request = { error: null, onerror: null };
            queue.push(() => {
              const stored = { ...row };
              if (stored.id === undefined) stored.id = nextArticleId++;
              articles.set(stored.id, stored);
            });
            return request;
          }
        }),
        abort() {
          if (finished) return;
          finished = true;
          tx.onabort && tx.onabort();
        }
      };

      const flush = () => {
        if (finished) return;
        while (queue.length > 0) {
          queue.shift()();
        }
        finished = true;
        tx.oncomplete && tx.oncomplete();
      };
      // Dispatch on a microtask: an empty transaction completes too,
      // and the caller attaches oncomplete synchronously after next(0).
      queueMicrotask(flush);
      return tx;
    }
  };

  return service;
}

globalThis.chrome = makeChrome();
globalThis.storageService = makeStorageService();
const { syncManager, SyncManager } = require('../js/sync-manager.js');

// Fresh stores per test: the module-level singletons are resolved
// through the globals at CALL time, so reassigning them here gives
// every test an isolated profile.
function resetProfile() {
  globalThis.chrome = makeChrome();
  globalThis.storageService = makeStorageService();
}
resetProfile();

const snapshot = (data, timestamp = 1000) => ({
  version: '1.0',
  deviceId: 'd',
  timestamp,
  data: {
    feeds: [], articles: [], settings: {}, readStatus: {}, savedArticles: [], folders: [],
    ...data
  }
});

test('F1: colliding feed ids — articles land under the RIGHT local feed, no duplicates', async () => {
  resetProfile();
  // The R4-14 fixture, taken one step further through applyMergedData:
  // local feed id 1 is url A (already stored locally with an article),
  // remote feed id 1 is url B (new here). The old apply phase keyed its
  // id map by BARE source id, so B's new local id clobbered A's mapping
  // and every article of A was written under B.
  const local = snapshot({
    feeds: [{ id: 1, url: 'https://a.example/feed', title: 'A', updatedAt: '2026-01-01' }],
    articles: [{ id: 10, feedId: 1, guid: 'x', title: 'Belongs to A', updatedAt: '2026-01-01' }]
  });
  const remote = snapshot({
    feeds: [{ id: 1, url: 'https://b.example/feed', title: 'B', updatedAt: '2026-01-02' }],
    articles: [{ id: 20, feedId: 1, guid: 'y', title: 'Belongs to B', updatedAt: '2026-01-02' }]
  });

  // Seed the "local profile" stores exactly as the snapshot describes.
  await storageService.addFeed({ url: 'https://a.example/feed', title: 'A' });
  await new Promise((resolve) => {
    const tx = storageService.db.transaction();
    const put = tx.objectStore().put({ id: 10, feedId: 1, guid: 'x', title: 'Belongs to A' });
    put.onerror = () => {};
    tx.oncomplete = () => resolve();
  });

  const merged = SyncManager.prototype.mergeData.call(syncManager, local, remote);
  await syncManager.applyMergedData(merged);

  const feeds = Array.from(storageService._feeds.values());
  assert.equal(feeds.length, 2, 'url A stays, url B is created');
  const feedA = feeds.find(f => f.url === 'https://a.example/feed');
  const feedB = feeds.find(f => f.url === 'https://b.example/feed');
  assert.ok(feedA && feedB);
  assert.equal(feedA.id, 1, 'the existing local row for A is kept');
  assert.notEqual(feedB.id, feedA.id);

  const rows = Array.from(storageService._articles.values());
  assert.equal(rows.length, 2, 'no duplicated article rows');
  const rowX = rows.find(r => r.guid === 'x');
  const rowY = rows.find(r => r.guid === 'y');
  assert.equal(rowX.feedId, feedA.id, 'article x lands under A');
  assert.equal(rowY.feedId, feedB.id, 'article y lands under B');
  assert.equal(
    rows.filter(r => r.feedId === feedB.id).length, 1,
    'no article of A was re-attributed to B');
});

test('F1: colliding folder ids — winning feeds land in the RIGHT folders', async () => {
  resetProfile();
  // Local folder id 2 is "News"; remote folder id 2 is "Tech". A feed
  // of each side references folder id 2. The old apply phase keyed
  // folder resolution by bare id, patching at least one feed into the
  // wrong folder.
  const local = snapshot({
    folders: [{ id: 2, name: 'News', parentId: null }],
    feeds: [{ id: 1, url: 'https://a.example/feed', title: 'A', folderId: 2, updatedAt: '2026-01-01' }],
    articles: []
  });
  const remote = snapshot({
    folders: [{ id: 2, name: 'Tech', parentId: null }],
    feeds: [{ id: 1, url: 'https://b.example/feed', title: 'B', folderId: 2, updatedAt: '2026-01-02' }],
    articles: []
  });

  // Local profile already stores folder 2 "News" and feed A inside it.
  await storageService.addFolder('News', null);
  await storageService.addFeed({ url: 'https://a.example/feed', title: 'A', folderId: 2 });

  const merged = SyncManager.prototype.mergeData.call(syncManager, local, remote);
  await syncManager.applyMergedData(merged);

  const folders = Array.from(storageService._folders.values());
  const news = folders.find(f => f.name === 'News');
  const tech = folders.find(f => f.name === 'Tech');
  assert.ok(news, 'the local News folder is untouched');
  assert.ok(tech, 'the remote Tech folder is imported');
  assert.equal(tech.parentId, null, 'Tech is a root folder, like on its origin profile');
  assert.notEqual(news.id, tech.id);

  const feedA = Array.from(storageService._feeds.values()).find(f => f.url.includes('a.example'));
  const feedB = Array.from(storageService._feeds.values()).find(f => f.url.includes('b.example'));
  assert.equal(feedA.folderId, news.id, 'A stays in News');
  assert.equal(feedB.folderId, tech.id, 'B is created inside Tech');
});

test('F1: a remote child folder imports under its full remote path even when its parent was a path-duplicate', async () => {
  resetProfile();
  // Local has "A"; remote has "A/B". Remote A is dropped by the merge
  // (same path as local A), but remote B must import as a CHILD of the
  // local A — not as a root folder named B.
  const local = snapshot({
    folders: [{ id: 1, name: 'A', parentId: null }],
    feeds: []
  });
  const remote = snapshot({
    folders: [
      { id: 5, name: 'A', parentId: null },
      { id: 6, name: 'B', parentId: 5 }
    ],
    feeds: []
  });

  await storageService.addFolder('A', null);

  const merged = SyncManager.prototype.mergeData.call(syncManager, local, remote);
  await syncManager.applyMergedData(merged);

  const folders = Array.from(storageService._folders.values());
  const a = folders.find(f => f.name === 'A' && f.parentId === null);
  const b = folders.find(f => f.name === 'B');
  assert.ok(a && b, 'both folders exist');
  assert.equal(b.parentId, a.id, 'remote A/B nests under the local A');
});

test('F6: getSyncData reads the settings the extension actually uses (chrome.storage.local)', async () => {
  resetProfile();
  await chrome.storage.local.set({
    settings: { apiUrl: 'http://192.168.1.10:3000', preferSidePanel: true },
    settingsModifiedAt: 42
  });

  const data = await syncManager.getSyncData();
  assert.equal(data.data.settings.apiUrl, 'http://192.168.1.10:3000',
    'the exported settings come from the local settings object, not the untouched sync area');
  assert.equal(data.timestamp, 42);
  assert.deepEqual(await chrome.storage.sync.get(null), {},
    'the sync storage area is never read or written');
});

test('F6: a winning remote settings merge lands in chrome.storage.local', async () => {
  resetProfile();
  await chrome.storage.local.set({
    settings: { apiUrl: 'http://old:3000' },
    settingsModifiedAt: 100
  });

  const local = await syncManager.getSyncData();
  const remote = snapshot(
    { settings: { apiUrl: 'http://new:3000', preferSidePanel: true } },
    900
  );
  const merged = SyncManager.prototype.mergeData.call(syncManager, local, remote);
  assert.equal(merged.settingsFromRemote, true);
  await syncManager.applyMergedData(merged);

  const { settings } = await chrome.storage.local.get('settings');
  assert.equal(settings.apiUrl, 'http://new:3000',
    'the merged settings are written where config.js/background.js read them');
  assert.equal(settings.preferSidePanel, true);
  const { settingsModifiedAt } = await chrome.storage.local.get('settingsModifiedAt');
  assert.ok(settingsModifiedAt > 100, 'the merge clock advances so the next export carries the new state');
  assert.deepEqual(await chrome.storage.sync.get(null), {});
});

test('F6: an empty winning settings object (legacy export) never wipes local settings', async () => {
  resetProfile();
  await chrome.storage.local.set({
    settings: { apiUrl: 'http://mine:3000' },
    settingsModifiedAt: 100
  });

  // Old exports were written while settings sync read the unused
  // chrome.storage.sync area, so their settings object is always {}.
  const local = await syncManager.getSyncData();
  const remote = snapshot({ settings: {} }, 900);
  const merged = SyncManager.prototype.mergeData.call(syncManager, local, remote);
  assert.equal(merged.settingsFromRemote, true);
  await syncManager.applyMergedData(merged);

  const { settings } = await chrome.storage.local.get('settings');
  assert.equal(settings.apiUrl, 'http://mine:3000',
    'an empty object has nothing to apply; the real settings survive');
  const { settingsModifiedAt } = await chrome.storage.local.get('settingsModifiedAt');
  assert.equal(settingsModifiedAt, 100,
    'the merge clock does not advance when nothing was applied');
});
