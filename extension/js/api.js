// API Service for browser extension
class ApiService {
  // Tokens are read from chrome.storage.local on every request. The service
  // worker can suspend at any time, so caching tokens on the instance risks
  // stale copies (spurious 401s after login/logout elsewhere or after a
  // SW wake). chrome.storage reads are async and cheap enough per call.
  async getAuthTokens() {
    const { access_token, refresh_token } = await chrome.storage.local.get(['access_token', 'refresh_token']);
    return { token: access_token || null, refreshToken: refresh_token || null };
  }

  async getBaseUrl() {
    if (typeof getApiBaseUrl === 'function') {
      return getApiBaseUrl();
    }
    const { settings } = await chrome.storage.local.get('settings');
    const root = (settings && settings.apiUrl) || DEFAULT_SERVER_URL || 'http://localhost:3000';
    return root.replace(/\/+$/, '').replace(/\/api$/, '') + '/api';
  }

  async request(endpoint, options = {}) {
    const url = `${await this.getBaseUrl()}${endpoint}`;
    const isFormData = typeof FormData !== 'undefined' && options.body instanceof FormData;
    const headers = isFormData ? { ...options.headers } : { 'Content-Type': 'application/json', ...options.headers };

    const isAuthFree = endpoint.startsWith('/auth/login') ||
      endpoint.startsWith('/auth/register') ||
      endpoint.startsWith('/auth/refresh');

    const { token, refreshToken } = await this.getAuthTokens();
    if (token && !isAuthFree) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    const buildInit = () => ({
      ...options,
      headers,
      body: options.body === undefined
        ? undefined
        : (isFormData ? options.body : JSON.stringify(options.body))
    });

    const sessionAtStart = await getAuthSession();
    let response = await fetch(url, buildInit());

    if (response.status === 401 && refreshToken && !isAuthFree && !options.skipRefresh) {
      // Transient refresh failures (network, 5xx) throw with credentials
      // left intact; only a definitive 401/403 clears them (inside
      // refreshAccessToken). The retry is abandoned when a login/logout
      // rotated the session mid-flight — replaying the body under
      // whichever credentials are stored now could hit the wrong account.
      let refreshed = false;
      try {
        refreshed = await this.refreshAccessToken();
      } catch (refreshError) {
        throw refreshError;
      }
      if (await getAuthSession() !== sessionAtStart) {
        const error = new Error('Session changed during request');
        error.status = 401;
        throw error;
      }
      if (refreshed) {
        const { token: newToken } = await this.getAuthTokens();
        if (newToken) {
          headers['Authorization'] = `Bearer ${newToken}`;
          response = await fetch(url, buildInit());
        }
      }
    }

    if (!response.ok) {
      // Surface the server's error message (e.g. "Selector matched 0
      // elements on ...") so callers can show something actionable.
      let message = `API error: ${response.status} ${response.statusText}`;
      try {
        const body = await response.json();
        if (body && typeof body.error === 'string' && body.error) {
          message = body.error;
        }
      } catch (err) {
        // Non-JSON error body - keep the generic message.
      }
      const error = new Error(message);
      error.status = response.status;
      throw error;
    }

    // 204/205 and empty bodies decode to null instead of throwing a JSON
    // parse error on a successful response.
    if (response.status === 204 || response.status === 205) {
      return null;
    }

    if (options.textResponse) {
      return response.text();
    }

    const text = await response.text();
    return text.trim() ? JSON.parse(text) : null;
  }

  // Refresh binds to the {session, refreshToken, baseUrl} it started with
  // and only writes when all three are still current — a refresh racing a
  // logout (tokens cleared) or a login (another account stored) can never
  // resurrect or overwrite credentials. Only a definitive 401/403 clears
  // tokens; any other failure propagates with credentials intact.
  async refreshAccessToken() {
    const { refreshToken } = await this.getAuthTokens();
    if (!refreshToken) {
      return false;
    }

    const baseUrl = await this.getBaseUrl();
    const session = await getAuthSession();

    let response;
    try {
      response = await fetch(`${baseUrl}/auth/refresh`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refreshToken })
      });
    } catch (error) {
      if (error && error.name === 'AbortError') {
        throw error;
      }
      const wrapped = new Error('Token refresh failed: network error');
      wrapped.status = 0;
      throw wrapped;
    }

    if (response.status === 401 || response.status === 403) {
      await withAuthLock(async () => {
        if (await getAuthSession() !== session) return;
        const tokens = await this.getAuthTokens();
        if (tokens.refreshToken !== refreshToken) return;
        await chrome.storage.local.remove(['access_token', 'refresh_token']);
      });
      return false;
    }

    if (!response.ok) {
      const error = new Error(`Token refresh failed: HTTP ${response.status}`);
      error.status = response.status;
      throw error;
    }

    const data = await response.json();
    const token = data.accessToken || data.token || null;
    if (!token) {
      return false;
    }

    await withAuthLock(async () => {
      if (await getAuthSession() !== session) return;
      const tokens = await this.getAuthTokens();
      if (tokens.refreshToken !== refreshToken) return;
      await chrome.storage.local.set({
        access_token: token,
        refresh_token: data.refreshToken || refreshToken
      });
    });
    return true;
  }

  // Auth methods
  async login(email, password) {
    const response = await this.request('/auth/login', {
      method: 'POST',
      body: { emailOrUsername: email, password }
    });

    // Rotate the session AFTER the new tokens land so any in-flight
    // refresh from the previous session cannot overwrite them.
    await withAuthLock(async () => {
      await chrome.storage.local.set({
        access_token: response.accessToken || response.token || null,
        refresh_token: response.refreshToken || null,
        user: response.user || null
      });
      await rotateAuthSession();
    });

    return response;
  }

  async logout() {
    try {
      // No refresh attempt: the tokens are about to be removed, and a 401
      // here must not resurrect them or race the removal.
      await this.request('/auth/logout', { method: 'POST', skipRefresh: true });
    } catch (e) {
      // Ignore logout errors
    }

    await withAuthLock(async () => {
      await chrome.storage.local.remove(['access_token', 'refresh_token', 'user', 'auth']);
      await rotateAuthSession();
    });
  }

  async getCurrentUser() {
    return this.request('/users/me');
  }

  // Feed methods
  async getFeeds() {
    return this.request('/feeds');
  }

  async getFeed(feedId) {
    return this.request(`/feeds/${feedId}`);
  }

  async createFeed(url, folderId = null, fullTextEnabled) {
    const body = folderId ? { url, folderId } : { url };
    if (typeof fullTextEnabled === 'boolean') {
      body.fullTextEnabled = fullTextEnabled;
    }
    return this.request('/feeds', {
      method: 'POST',
      body
    });
  }

  // Page feed: items are scraped from an HTML page via CSS selector
  // (POST /api/feeds/page). Requires a server connection.
  async createPageFeed({ pageUrl, pageSelector, title, folderId, updateInterval } = {}) {
    const body = { pageUrl, pageSelector };
    if (title) body.title = title;
    if (folderId) body.folderId = folderId;
    if (updateInterval) body.updateInterval = updateInterval;
    return this.request('/feeds/page', {
      method: 'POST',
      body
    });
  }

  async deleteFeed(feedId) {
    return this.request(`/feeds/${feedId}`, {
      method: 'DELETE'
    });
  }

  async refreshFeed(feedId) {
    return this.request(`/feeds/${feedId}/refresh`, {
      method: 'POST'
    });
  }

  // Article methods
  async getArticles({ feedId = null, unread = false, starred = false, page = 1, limit = 20 } = {}) {
    const params = new URLSearchParams();
    if (feedId) params.set('feedId', feedId);
    if (unread) params.set('isRead', 'false');
    if (starred) params.set('isStarred', 'true');
    params.set('page', String(page));
    params.set('limit', String(limit));
    return this.request(`/articles?${params.toString()}`);
  }

  async getArticle(articleId) {
    return this.request(`/articles/${articleId}`);
  }

  async markArticleRead(articleId, isRead = true) {
    return this.request(`/articles/${articleId}/state`, {
      method: 'PUT',
      body: { isRead }
    });
  }

  async markArticleSaved(articleId, isSaved = true) {
    return this.request(`/articles/${articleId}/state`, {
      method: 'PUT',
      body: { isStarred: isSaved }
    });
  }

  async markAllRead(feedId = null) {
    return feedId
      ? this.request(`/feeds/${feedId}/mark-all-read`, { method: 'POST' })
      : this.request('/articles/mark-all-read', { method: 'POST', body: {} });
  }

  // Folder methods
  async getFolders() {
    return this.request('/folders');
  }

  async createFolder(name) {
    return this.request('/folders', {
      method: 'POST',
      body: { name }
    });
  }

  // OPML methods
  async importOPML(opmlContent) {
    const form = new FormData();
    form.append('file', new Blob([opmlContent], { type: 'text/xml' }), 'opml.xml');
    return this.request('/discovery/import/opml', {
      method: 'POST',
      body: form
    });
  }

  async exportOPML() {
    return this.request('/discovery/export/opml', {
      method: 'GET',
      textResponse: true
    });
  }

  // Reading stats
  async getStats() {
    return this.request('/stats/overview');
  }
}

// Create global instance (service workers have no window)
globalThis.apiService = new ApiService();

// Exported for the node test runner only; extension contexts load this
// file as a classic script where apiService is a plain global.
if (typeof module !== 'undefined') {
  module.exports = { ApiService, apiService };
}
