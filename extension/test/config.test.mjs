// Tests for extension/js/config.js — server switching and the locked
// saved-articles mutations. Plain `node --test`, no deps: chrome.storage is
// stubbed with a Map.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

function makeChrome() {
  const storage = new Map();
  const area = {
    get: async (keys) => {
      const out = {};
      if (typeof keys === 'string') {
        if (storage.has(keys)) out[keys] = storage.get(keys);
        return out;
      }
      for (const key of Array.isArray(keys) ? keys : Object.keys(keys)) {
        if (storage.has(key)) out[key] = storage.get(key);
      }
      return out;
    },
    set: async (obj) => {
      for (const [key, value] of Object.entries(obj)) storage.set(key, value);
    },
    remove: async (keys) => {
      for (const key of Array.isArray(keys) ? keys : [keys]) storage.delete(key);
    },
  };
  return { storage: { local: area }, _storage: storage };
}

function loadConfig(chromeStub) {
  globalThis.chrome = chromeStub;
  delete require.cache[require.resolve('../js/config.js')];
  return require('../js/config.js');
}

test('setServerConnection drops the old server\'s credentials and rotates the session on change', async () => {
  const chromeStub = makeChrome();
  chromeStub._storage.set('settings', { apiUrl: 'http://server-a:3000' });
  chromeStub._storage.set('access_token', 'a-token');
  chromeStub._storage.set('refresh_token', 'r-token');
  chromeStub._storage.set('user', { id: 'u1' });
  chromeStub._storage.set('offlineFeeds', [1]);
  chromeStub._storage.set('auth_session', 'old-session');
  const config = loadConfig(chromeStub);

  const result = await config.setServerConnection('http://server-b:3000/');

  assert.equal(result.changed, true);
  assert.equal(result.apiUrl, 'http://server-b:3000');
  assert.equal(chromeStub._storage.get('access_token'), undefined);
  assert.equal(chromeStub._storage.get('refresh_token'), undefined);
  assert.equal(chromeStub._storage.get('user'), undefined);
  assert.equal(chromeStub._storage.get('offlineFeeds'), undefined);
  assert.equal(chromeStub._storage.get('settings').apiUrl, 'http://server-b:3000');
  assert.notEqual(chromeStub._storage.get('auth_session'), 'old-session');
});

test('setServerConnection is a no-op when the URL is unchanged', async () => {
  const chromeStub = makeChrome();
  chromeStub._storage.set('settings', { apiUrl: 'http://server-a:3000' });
  chromeStub._storage.set('access_token', 'a-token');
  const config = loadConfig(chromeStub);

  const result = await config.setServerConnection('http://server-a:3000');

  assert.equal(result.changed, false);
  assert.equal(chromeStub._storage.get('access_token'), 'a-token');
});

test('setServerConnection rejects malformed origins', async () => {
  const config = loadConfig(makeChrome());
  await assert.rejects(() => config.setServerConnection('not a url'));
  await assert.rejects(() => config.setServerConnection('ftp://x.example'));
  await assert.rejects(() => config.setServerConnection('http://user:pass@x.example'));
});

test('savedArticlesAdd dedupes by URL and returns the EXISTING item id', async () => {
  const chromeStub = makeChrome();
  const config = loadConfig(chromeStub);

  const first = await config.savedArticlesAdd({ url: 'https://x.example/a', title: 'A' });
  assert.equal(first.alreadySaved, false);
  assert.ok(first.item.id);
  assert.equal(first.list.length, 1);

  const second = await config.savedArticlesAdd({ url: 'https://x.example/a', title: 'A again' });
  assert.equal(second.alreadySaved, true);
  assert.equal(second.item.id, first.item.id);
  assert.equal(second.list.length, 1);

  const third = await config.savedArticlesAdd({ url: 'https://x.example/b', title: 'B' });
  assert.equal(third.alreadySaved, false);
  assert.notEqual(third.item.id, first.item.id);
  assert.equal(third.list.length, 2);
});

test('savedArticlesRemove filters by id', async () => {
  const chromeStub = makeChrome();
  const config = loadConfig(chromeStub);

  const a = await config.savedArticlesAdd({ url: 'https://x.example/a' });
  await config.savedArticlesAdd({ url: 'https://x.example/b' });
  const { list } = await config.savedArticlesRemove(a.item.id);

  assert.equal(list.length, 1);
  assert.equal(list[0].url, 'https://x.example/b');
});
