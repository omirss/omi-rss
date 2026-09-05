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

    let response = await fetch(url, buildInit());

    if (response.status === 401 && refreshToken && !isAuthFree) {
      const refreshed = await this.refreshAccessToken();
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

    if (options.textResponse) {
      return response.text();
    }

    return response.json();
  }

  async refreshAccessToken() {
    const { refreshToken } = await this.getAuthTokens();
    if (!refreshToken) {
      return false;
    }

    try {
      const response = await fetch(`${await this.getBaseUrl()}/auth/refresh`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refreshToken })
      });

      if (response.ok) {
        const data = await response.json();
        const token = data.accessToken || data.token || null;
        if (token) {
          await chrome.storage.local.set({
            access_token: token,
            refresh_token: data.refreshToken || refreshToken
          });
          return true;
        }
      }
    } catch (error) {
      console.error('Token refresh failed:', error);
    }

    await chrome.storage.local.remove(['access_token', 'refresh_token']);
    return false;
  }

  // Auth methods
  async login(email, password) {
    const response = await this.request('/auth/login', {
      method: 'POST',
      body: { emailOrUsername: email, password }
    });

    await chrome.storage.local.set({
      access_token: response.accessToken || response.token || null,
      refresh_token: response.refreshToken || null,
      user: response.user || null
    });

    return response;
  }

  async logout() {
    try {
      await this.request('/auth/logout', { method: 'POST' });
    } catch (e) {
      // Ignore logout errors
    }

    await chrome.storage.local.remove(['access_token', 'refresh_token', 'user', 'auth']);
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

  async createFeed(url, folderId = null) {
    return this.request('/feeds', {
      method: 'POST',
      body: folderId ? { url, folderId } : { url }
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
