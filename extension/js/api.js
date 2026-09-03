// API Service for browser extension
class ApiService {
  constructor() {
    this.baseUrl = 'http://localhost:8080/api'; // Default for development
    this.token = null;
    this.refreshToken = null;
    this.initializeAuth();
  }

  async initializeAuth() {
    const auth = await chrome.storage.local.get(['access_token', 'refresh_token']);
    this.token = auth.access_token;
    this.refreshToken = auth.refresh_token;
  }

  async request(endpoint, options = {}) {
    const url = `${this.baseUrl}${endpoint}`;
    
    const headers = {
      'Content-Type': 'application/json',
      ...options.headers
    };

    // Add auth token if available
    if (this.token && !endpoint.includes('/auth/login') && !endpoint.includes('/auth/register')) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }

    try {
      const response = await fetch(url, {
        ...options,
        headers,
        body: options.body ? JSON.stringify(options.body) : undefined
      });

      // Handle token refresh
      if (response.status === 401 && this.refreshToken) {
        const refreshed = await this.refreshAccessToken();
        if (refreshed) {
          // Retry original request with new token
          headers['Authorization'] = `Bearer ${this.token}`;
          return fetch(url, { ...options, headers, body: options.body ? JSON.stringify(options.body) : undefined });
        }
      }

      if (!response.ok) {
        throw new Error(`API error: ${response.status} ${response.statusText}`);
      }

      return response.json();
    } catch (error) {
      console.error('API request failed:', error);
      throw error;
    }
  }

  async refreshAccessToken() {
    try {
      const response = await fetch(`${this.baseUrl}/auth/refresh`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refreshToken: this.refreshToken })
      });

      if (response.ok) {
        const data = await response.json();
        this.token = data.accessToken;
        this.refreshToken = data.refreshToken;
        
        // Save to storage
        await chrome.storage.local.set({
          access_token: this.token,
          refresh_token: this.refreshToken
        });
        
        return true;
      }
    } catch (error) {
      console.error('Token refresh failed:', error);
    }
    
    // Clear auth on refresh failure
    await this.logout();
    return false;
  }

  // Auth methods
  async login(email, password) {
    const response = await this.request('/auth/login', {
      method: 'POST',
      body: { email, password }
    });

    this.token = response.accessToken;
    this.refreshToken = response.refreshToken;
    
    await chrome.storage.local.set({
      access_token: this.token,
      refresh_token: this.refreshToken,
      user: response.user
    });

    return response;
  }

  async logout() {
    try {
      await this.request('/auth/logout', { method: 'POST' });
    } catch (e) {
      // Ignore logout errors
    }

    this.token = null;
    this.refreshToken = null;
    await chrome.storage.local.remove(['access_token', 'refresh_token', 'user']);
  }

  async getCurrentUser() {
    return this.request('/user/me');
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
      body: { url, folderId }
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
  async getArticles(params = {}) {
    const queryParams = new URLSearchParams(params).toString();
    return this.request(`/articles${queryParams ? '?' + queryParams : ''}`);
  }

  async getArticle(articleId) {
    return this.request(`/articles/${articleId}`);
  }

  async markArticleRead(articleId, isRead) {
    return this.request(`/articles/${articleId}/read`, {
      method: 'PUT',
      body: { isRead }
    });
  }

  async markArticleSaved(articleId, isSaved) {
    return this.request(`/articles/${articleId}/saved`, {
      method: 'PUT',
      body: { isSaved }
    });
  }

  async markAllRead(feedId = null) {
    return this.request('/articles/mark-all-read', {
      method: 'POST',
      body: feedId ? { feedId } : {}
    });
  }

  // Save current page as article
  async savePageAsArticle(pageData) {
    return this.request('/articles/save-page', {
      method: 'POST',
      body: pageData
    });
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
    return this.request('/feeds/import-opml', {
      method: 'POST',
      body: { opmlContent }
    });
  }

  async exportOPML() {
    return this.request('/feeds/export-opml');
  }

  // Analytics
  async getAnalytics() {
    return this.request('/analytics');
  }
}

// Create global instance
window.apiService = new ApiService();