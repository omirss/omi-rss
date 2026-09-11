// Shared configuration helpers - single source of truth for server URL and auth token.
// Canonical chrome.storage.local keys:
//   settings.apiUrl  - server root URL (e.g. http://localhost:3000), default DEFAULT_SERVER_URL
//   access_token     - JWT access token
//   refresh_token    - JWT refresh token (may be absent)
//   user             - cached user object
//   auth_session     - session generation; rotated on login/logout/server
//                     change so late token writes cannot resurrect or swap
//                     sessions across boundaries

const DEFAULT_SERVER_URL = 'http://localhost:3000';

function normalizeServerUrl(raw) {
  return String(raw || '').trim().replace(/\/+$/, '').replace(/\/api$/, '');
}

async function getServerUrl() {
  const { settings } = await chrome.storage.local.get('settings');
  const raw = (settings && settings.apiUrl) || DEFAULT_SERVER_URL;
  return normalizeServerUrl(raw) || DEFAULT_SERVER_URL;
}

async function getApiBaseUrl() {
  return (await getServerUrl()) + '/api';
}

async function getAccessToken() {
  const { access_token } = await chrome.storage.local.get('access_token');
  return access_token || null;
}

function generateSessionId() {
  return (typeof crypto !== 'undefined' && crypto.randomUUID)
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

// Serializes a callback against every other withAuthLock caller in this
// extension context (Web Locks; Falls back to direct execution when
// unavailable).
async function withAuthLock(fn) {
  if (typeof navigator !== 'undefined' && navigator.locks && navigator.locks.request) {
    return navigator.locks.request('omi-auth-state', () => fn());
  }
  return fn();
}

async function rotateAuthSession() {
  const session = generateSessionId();
  await chrome.storage.local.set({ auth_session: session });
  return session;
}

async function getAuthSession() {
  const { auth_session } = await chrome.storage.local.get('auth_session');
  return auth_session || null;
}

// The only sanctioned way to change the server: validates the origin and,
// when it actually changes, drops the previous server's tokens/user and
// cached offline data and rotates the session — the next request must
// never carry the old server's credentials to the new one.
async function setServerConnection(raw) {
  const normalized = normalizeServerUrl(raw) || DEFAULT_SERVER_URL;
  let parsed;
  try {
    parsed = new URL(normalized);
  } catch (error) {
    throw new Error('Invalid server URL');
  }
  if (
    (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') ||
    parsed.username || parsed.password || parsed.search || parsed.hash
  ) {
    throw new Error('Server URL must be a plain http(s) origin');
  }

  return withAuthLock(async () => {
    const { settings: current = {} } = await chrome.storage.local.get('settings');
    const currentUrl = normalizeServerUrl(current.apiUrl) || DEFAULT_SERVER_URL;
    if (normalized === currentUrl) {
      return { changed: false, apiUrl: normalized };
    }
    await chrome.storage.local.set({ settings: { ...current, apiUrl: normalized } });
    await chrome.storage.local.remove([
      'access_token', 'refresh_token', 'user', 'auth',
      'offlineFeeds', 'offlineArticles', 'offlineMode'
    ]);
    await rotateAuthSession();
    return { changed: true, apiUrl: normalized };
  });
}

// Saved-articles list mutations: read-modify-write under a Web Lock so the
// popup and the background worker can never lose or resurrect each
// other's entries, and duplicate saves return the EXISTING item's id.
async function withSavedArticlesLock(fn) {
  if (typeof navigator !== 'undefined' && navigator.locks && navigator.locks.request) {
    return navigator.locks.request('omi-library', () => fn());
  }
  return fn();
}

async function savedArticlesAdd(item) {
  return withSavedArticlesLock(async () => {
    const { savedArticles = [] } = await chrome.storage.local.get('savedArticles');
    const existing = item.url ? savedArticles.find(a => a.url === item.url) : null;
    if (existing) {
      return { list: savedArticles, alreadySaved: true, item: existing };
    }
    const entry = {
      type: 'article',
      ...item,
      id: (typeof crypto !== 'undefined' && crypto.randomUUID)
        ? crypto.randomUUID()
        : generateSessionId(),
      savedAt: new Date().toISOString()
    };
    const list = [entry, ...savedArticles];
    await chrome.storage.local.set({ savedArticles: list });
    return { list, alreadySaved: false, item: entry };
  });
}

async function savedArticlesRemove(id) {
  return withSavedArticlesLock(async () => {
    const { savedArticles = [] } = await chrome.storage.local.get('savedArticles');
    const list = savedArticles.filter(a => a.id !== id);
    await chrome.storage.local.set({ savedArticles: list });
    return { list };
  });
}

// Exported for the node test runner only; extension contexts load this
// file as a classic script where these are plain globals.
if (typeof module !== 'undefined') {
  module.exports = {
    normalizeServerUrl,
    getServerUrl,
    getApiBaseUrl,
    getAccessToken,
    withAuthLock,
    rotateAuthSession,
    getAuthSession,
    setServerConnection,
    savedArticlesAdd,
    savedArticlesRemove
  };
}
