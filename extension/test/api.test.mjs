// Tests for extension/js/api.js refresh/session semantics and 204
// handling. Plain `node --test`, no deps: chrome.storage is stubbed with a
// Map and fetch is stubbed per test.
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

function loadApi(chromeStub) {
  globalThis.chrome = chromeStub;
  delete require.cache[require.resolve('../js/config.js')];
  delete require.cache[require.resolve('../js/api.js')];
  // In the extension these are classic-script globals; mirror that for the
  // required module.
  Object.assign(globalThis, require('../js/config.js'));
  const api = require('../js/api.js');
  return api.apiService;
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' }
  });
}

test('a successful 204 resolves to null instead of a JSON parse failure', async () => {
  const chromeStub = makeChrome();
  chromeStub._storage.set('settings', { apiUrl: 'http://localhost:3000' });
  const api = loadApi(chromeStub);
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(null, { status: 204 });

  try {
    const result = await api.deleteFeed('x');
    assert.equal(result, null);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('a transient refresh failure (503) keeps credentials and propagates', async () => {
  const chromeStub = makeChrome();
  chromeStub._storage.set('settings', { apiUrl: 'http://localhost:3000' });
  chromeStub._storage.set('access_token', 'a');
  chromeStub._storage.set('refresh_token', 'r');
  chromeStub._storage.set('auth_session', 's1');
  const api = loadApi(chromeStub);
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url) => {
    if (String(url).includes('/auth/refresh')) return jsonResponse({ error: 'busy' }, 503);
    return jsonResponse({ error: 'Token expired' }, 401);
  };

  try {
    await assert.rejects(() => api.getFeeds());
    assert.equal(chromeStub._storage.get('access_token'), 'a');
    assert.equal(chromeStub._storage.get('refresh_token'), 'r');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('a definitive refresh rejection (401) clears the credentials', async () => {
  const chromeStub = makeChrome();
  chromeStub._storage.set('settings', { apiUrl: 'http://localhost:3000' });
  chromeStub._storage.set('access_token', 'a');
  chromeStub._storage.set('refresh_token', 'r');
  chromeStub._storage.set('auth_session', 's1');
  const api = loadApi(chromeStub);
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url) => {
    if (String(url).includes('/auth/refresh')) return jsonResponse({ error: 'Invalid refresh token' }, 401);
    return jsonResponse({ error: 'Token expired' }, 401);
  };

  try {
    await assert.rejects(() => api.getFeeds());
    assert.equal(chromeStub._storage.get('access_token'), undefined);
    assert.equal(chromeStub._storage.get('refresh_token'), undefined);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('a refresh completing after a logout cannot resurrect the cleared tokens', async () => {
  const chromeStub = makeChrome();
  chromeStub._storage.set('settings', { apiUrl: 'http://localhost:3000' });
  chromeStub._storage.set('access_token', 'a');
  chromeStub._storage.set('refresh_token', 'r');
  chromeStub._storage.set('auth_session', 's1');
  const api = loadApi(chromeStub);
  const originalFetch = globalThis.fetch;

  const refreshResolvers = [];
  globalThis.fetch = async (url) => {
    if (String(url).includes('/auth/refresh')) {
      return new Promise((resolve) => { refreshResolvers.push(resolve); });
    }
    return jsonResponse({ error: 'Token expired' }, 401);
  };

  try {
    const pending = api.getFeeds();
    await new Promise((resolve) => setTimeout(resolve, 0));
    // Logout lands while the refresh is still in flight (logout rotates
    // the session and removes the tokens; its own 401 may also start a
    // second refresh — resolve them all).
    await api.logout();
    for (const resolve of refreshResolvers.splice(0)) {
      resolve(jsonResponse({ token: 'a2', refreshToken: 'r2' }));
    }
    await assert.rejects(() => pending, /Session changed|Token expired/);

    assert.equal(chromeStub._storage.get('access_token'), undefined);
    assert.equal(chromeStub._storage.get('refresh_token'), undefined);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('login rotates the session and stores the tokens under the lock', async () => {
  const chromeStub = makeChrome();
  chromeStub._storage.set('settings', { apiUrl: 'http://localhost:3000' });
  const api = loadApi(chromeStub);
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => jsonResponse({ token: 't1', refreshToken: 'r1', user: { id: 'u1' } });

  try {
    await api.login('user', 'pass');
    assert.equal(chromeStub._storage.get('access_token'), 't1');
    assert.equal(chromeStub._storage.get('refresh_token'), 'r1');
    assert.ok(chromeStub._storage.get('auth_session'));
  } finally {
    globalThis.fetch = originalFetch;
  }
});
