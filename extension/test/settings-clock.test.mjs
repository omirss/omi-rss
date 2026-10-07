// B1 regression: the settings-sync LWW clock (settingsModifiedAt) must
// START and TICK on every LOCAL settings mutation. Before the fix,
// nothing wrote the key on a local change, so between two real profiles
// the merge condition was `0 > 0` — remote settings could never win and
// the round-5 settings-sync path was unreachable (tests only passed by
// hand-seeding the clock).
//
// These tests drive the PRODUCTION write paths only — the background
// `update-settings` message handler (what every popup toggle goes
// through) and setServerConnection — and never seed
// settingsModifiedAt by hand. Plain `node --test`, no deps.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

// chrome stub with SEPARATE local and sync areas plus the listener
// surfaces background.js touches at load time.
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
      remove: async (keys) => {
        for (const key of Array.isArray(keys) ? keys : [keys]) storage.delete(key);
      }
    };
  };
  const listeners = { message: [] };
  const addListener = (list) => (fn) => list.push(fn);
  return {
    storage: { local: area(), sync: area() },
    runtime: {
      getURL: (path) => `chrome-extension://test/${path}`,
      onInstalled: { addListener: () => {} },
      onMessage: { addListener: addListener(listeners.message) },
      sendMessage: async () => {}
    },
    contextMenus: { onClicked: { addListener: () => {} } },
    commands: { onCommand: { addListener: () => {} } },
    action: { onClicked: { addListener: () => {} } },
    notifications: { onButtonClicked: { addListener: () => {} } },
    _messageListeners: listeners.message
  };
}

// In-memory stand-in for the IndexedDB storageService — the parts
// getSyncData/applySyncData rely on (exportAllData snapshot, folder
// path resolution, feed upserts, the single-store article transaction).
function makeStorageService() {
  let nextFeedId = 1;
  let nextFolderId = 1;
  let nextArticleId = 1;
  const feeds = new Map();
  const folders = new Map();
  const articles = new Map();

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
      for (const feed of feeds.values()) {
        if (feed.url === url) return { ...feed };
      }
      return null;
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
    }
  };

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
      queueMicrotask(flush);
      return tx;
    }
  };

  return service;
}

// Two independent in-memory profiles. Modules resolve `chrome` and
// `storageService` through the globals at CALL time, so swapping the
// globals swaps the profile.
function makeProfile() {
  return { chrome: makeChrome(), storageService: makeStorageService() };
}

function useProfile(profile) {
  globalThis.chrome = profile.chrome;
  globalThis.storageService = profile.storageService;
}

// The file format another profile would export/import.
const snapshot = (data, timestamp) => ({
  version: '1.0',
  deviceId: 'remote-device',
  timestamp,
  data: {
    feeds: [], articles: [], settings: {}, readStatus: {}, savedArticles: [], folders: [],
    ...data
  }
});

// Load the real modules once. background.js skips importScripts in
// node, so its globals (writeSettings, feedScheduler) must be provided.
useProfile(makeProfile());
const { syncManager } = require('../js/sync-manager.js');
const config = require('../js/config.js');
globalThis.writeSettings = config.writeSettings;
globalThis.feedScheduler = { start() {} };
require('../js/background.js');

// The background service worker's onMessage handler (registered last,
// after sync-manager.js's own). This is the entry point every popup
// settings toggle goes through.
const backgroundHandler =
  globalThis.chrome._messageListeners[globalThis.chrome._messageListeners.length - 1];

// Drive the production `update-settings` message path.
function updateSettingsViaBackground(settings) {
  return new Promise((resolve, reject) => {
    backgroundHandler(
      { action: 'update-settings', settings },
      {},
      (response) => (response && response.error
        ? reject(new Error(response.error))
        : resolve(response))
    );
  });
}

test('B1: a settings change through the production write path starts the LWW clock', async () => {
  const profile = makeProfile();
  useProfile(profile);

  assert.equal((await syncManager.getSyncData()).timestamp, 0,
    'precondition: a fresh profile carries clock 0');

  const response = await updateSettingsViaBackground({
    preferSidePanel: true,
    theme: 'light'
  });
  assert.equal(response.success, true);

  const data = await syncManager.getSyncData();
  assert.ok(data.timestamp > 0,
    'the exported clock is nonzero after a local settings change ' +
    '(before the fix nothing wrote settingsModifiedAt and the LWW ' +
    'merge could never let remote settings win)');
  assert.equal(data.data.settings.preferSidePanel, true);
  assert.equal(data.data.settings.theme, 'light');
});

test('B1: an older settings snapshot never overwrites newer local settings', async () => {
  const profile = makeProfile();
  useProfile(profile);

  await updateSettingsViaBackground({ apiUrl: 'http://mine:3000' });
  const localClock = (await syncManager.getSyncData()).timestamp;
  assert.ok(localClock > 0, 'precondition: the local clock ticks via the write path');

  // A file exported BEFORE the local change.
  await syncManager.applySyncData(snapshot(
    { settings: { apiUrl: 'http://theirs:3000' } },
    localClock - 60000
  ));

  const { settings } = await profile.chrome.storage.local.get('settings');
  assert.equal(settings.apiUrl, 'http://mine:3000',
    'local settings survive an older snapshot');
  const { settingsModifiedAt } = await profile.chrome.storage.local.get('settingsModifiedAt');
  assert.ok(settingsModifiedAt >= localClock,
    'the clock does not regress');
});

test('B1: a newer settings snapshot applies and advances the clock past the local one', async () => {
  const profile = makeProfile();
  useProfile(profile);

  await updateSettingsViaBackground({ apiUrl: 'http://old:3000' });
  const localClock = (await syncManager.getSyncData()).timestamp;
  // The write path and the import must land in different milliseconds
  // so "the clock advances" is observable (both stamp Date.now()).
  await new Promise(resolve => setTimeout(resolve, 5));

  // A file exported AFTER the local change (its timestamp is file
  // content, not a hand-seeded local clock).
  await syncManager.applySyncData(snapshot(
    { settings: { apiUrl: 'http://new:3000', preferSidePanel: true } },
    localClock + 60000
  ));

  const { settings } = await profile.chrome.storage.local.get('settings');
  assert.equal(settings.apiUrl, 'http://new:3000',
    'the newer remote settings win the LWW merge');
  assert.equal(settings.preferSidePanel, true);
  const { settingsModifiedAt } = await profile.chrome.storage.local.get('settingsModifiedAt');
  assert.ok(settingsModifiedAt > localClock,
    'the clock advances past the previous local value so the next export carries the new state');
});

test('B1: settings travel end-to-end between two fresh profiles', async () => {
  // Before the fix both clocks stayed 0, the merge was `0 > 0`, and
  // B's settings were never touched by A's export.
  const a = makeProfile();
  const b = makeProfile();

  useProfile(a);
  await updateSettingsViaBackground({
    apiUrl: 'http://192.168.1.20:3000',
    preferSidePanel: true,
    fullTextDefault: false
  });
  const exported = await syncManager.getSyncData();
  assert.ok(exported.timestamp > 0, 'A exports a running clock');

  useProfile(b);
  await syncManager.applySyncData(exported);

  const { settings } = await b.chrome.storage.local.get('settings');
  assert.deepEqual(settings, {
    apiUrl: 'http://192.168.1.20:3000',
    preferSidePanel: true,
    fullTextDefault: false
  }, 'B ends up with exactly the settings A wrote through the production path');
  const { settingsModifiedAt } = await b.chrome.storage.local.get('settingsModifiedAt');
  assert.ok(settingsModifiedAt > 0, "B's clock runs after the import");
});

test('B1: setServerConnection advances the LWW clock on a real server change', async () => {
  const profile = makeProfile();
  useProfile(profile);
  await profile.chrome.storage.local.set({
    settings: { apiUrl: 'http://server-a:3000' }
  });

  const result = await config.setServerConnection('http://server-b:3000');

  assert.equal(result.changed, true);
  const { settingsModifiedAt } = await profile.chrome.storage.local.get('settingsModifiedAt');
  assert.ok(settingsModifiedAt > 0,
    'switching servers is a settings mutation and must tick the clock');
});
