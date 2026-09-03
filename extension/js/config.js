// Shared configuration helpers - single source of truth for server URL and auth token.
// Canonical chrome.storage.local keys:
//   settings.apiUrl  - server root URL (e.g. http://localhost:3000), default DEFAULT_SERVER_URL
//   access_token     - JWT access token
//   refresh_token    - JWT refresh token (may be absent)
//   user             - cached user object

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
