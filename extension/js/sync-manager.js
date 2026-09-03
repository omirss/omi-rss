// Ultra-thin sync manager for Omi RSS browser extension
class SyncManager {
  constructor() {
    this.webrtcSync = null;
    this.fileSync = null;
    this.syncInProgress = false;
    this.lastSyncTime = null;
    this.init();
  }

  async init() {
    // Lazy load sync modules when needed
    const stored = await chrome.storage.local.get(['lastSyncTime', 'syncSettings']);
    this.lastSyncTime = stored.lastSyncTime;
    this.syncSettings = stored.syncSettings || { autoSync: false, syncInterval: 3600000 };
  }

  // Get all data for syncing
  async getSyncData() {
    const [feeds, articles, settings, readStatus, savedArticles, folders] = await Promise.all([
      this.getFeeds(),
      this.getArticles(),
      chrome.storage.sync.get(null),
      chrome.storage.local.get('readArticles'),
      chrome.storage.local.get('savedArticles'),
      chrome.storage.local.get('folders')
    ]);

    return {
      version: '1.0',
      deviceId: await this.getDeviceId(),
      timestamp: Date.now(),
      data: {
        feeds: feeds || [],
        articles: articles || [],
        settings: settings || {},
        readStatus: readStatus.readArticles || {},
        savedArticles: savedArticles.savedArticles || [],
        folders: folders.folders || []
      }
    };
  }

  // Apply sync data from another device
  async applySyncData(remoteData) {
    if (!remoteData || remoteData.version !== '1.0') {
      throw new Error('Invalid sync data format');
    }

    // Merge strategy: newer timestamps win, union for read/saved status
    const localData = await this.getSyncData();
    const merged = this.mergeData(localData, remoteData);

    // Apply merged data
    await Promise.all([
      this.saveFeeds(merged.data.feeds),
      this.saveArticles(merged.data.articles),
      chrome.storage.sync.set(merged.data.settings),
      chrome.storage.local.set({ readArticles: merged.data.readStatus }),
      chrome.storage.local.set({ savedArticles: merged.data.savedArticles }),
      chrome.storage.local.set({ folders: merged.data.folders })
    ]);

    this.lastSyncTime = Date.now();
    await chrome.storage.local.set({ lastSyncTime: this.lastSyncTime });
  }

  // Merge local and remote data
  mergeData(local, remote) {
    const merged = {
      version: '1.0',
      deviceId: local.deviceId,
      timestamp: Date.now(),
      data: {}
    };

    // Merge feeds - keep unique by URL
    const feedMap = new Map();
    [...local.data.feeds, ...remote.data.feeds].forEach(feed => {
      const existing = feedMap.get(feed.url);
      if (!existing || feed.updatedAt > existing.updatedAt) {
        feedMap.set(feed.url, feed);
      }
    });
    merged.data.feeds = Array.from(feedMap.values());

    // Merge articles - keep unique by guid
    const articleMap = new Map();
    [...local.data.articles, ...remote.data.articles].forEach(article => {
      const existing = articleMap.get(article.guid);
      if (!existing || article.updatedAt > existing.updatedAt) {
        articleMap.set(article.guid, article);
      }
    });
    merged.data.articles = Array.from(articleMap.values());

    // Merge read status - union
    merged.data.readStatus = {
      ...local.data.readStatus,
      ...remote.data.readStatus
    };

    // Merge saved articles - union
    merged.data.savedArticles = [
      ...new Set([...local.data.savedArticles, ...remote.data.savedArticles])
    ];

    // Merge settings - remote wins for now
    merged.data.settings = remote.timestamp > local.timestamp 
      ? remote.data.settings 
      : local.data.settings;

    // Merge folders
    const folderMap = new Map();
    [...local.data.folders, ...remote.data.folders].forEach(folder => {
      const existing = folderMap.get(folder.id);
      if (!existing || folder.updatedAt > existing.updatedAt) {
        folderMap.set(folder.id, folder);
      }
    });
    merged.data.folders = Array.from(folderMap.values());

    return merged;
  }

  // WebRTC sync methods
  async startWebRTCSync() {
    if (!this.webrtcSync) {
      const { WebRTCSync } = await import('./webrtc-sync.js');
      this.webrtcSync = new WebRTCSync(this);
    }
    return this.webrtcSync.createConnection();
  }

  async connectWebRTC(connectionData) {
    if (!this.webrtcSync) {
      const { WebRTCSync } = await import('./webrtc-sync.js');
      this.webrtcSync = new WebRTCSync(this);
    }
    return this.webrtcSync.connectToPeer(connectionData);
  }

  // File sync methods
  async exportToFile() {
    if (!this.fileSync) {
      const { FileSync } = await import('./file-sync.js');
      this.fileSync = new FileSync(this);
    }
    return this.fileSync.exportData();
  }

  async importFromFile(fileContent) {
    if (!this.fileSync) {
      const { FileSync } = await import('./file-sync.js');
      this.fileSync = new FileSync(this);
    }
    return this.fileSync.importData(fileContent);
  }

  // Helper methods
  async getDeviceId() {
    let { deviceId } = await chrome.storage.local.get('deviceId');
    if (!deviceId) {
      deviceId = `ext-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
      await chrome.storage.local.set({ deviceId });
    }
    return deviceId;
  }

  async getFeeds() {
    // Get feeds from local storage or API service
    const { feeds } = await chrome.storage.local.get('feeds');
    return feeds || [];
  }

  async getArticles() {
    // Get articles from local storage
    const { articles } = await chrome.storage.local.get('articles');
    return articles || [];
  }

  async saveFeeds(feeds) {
    await chrome.storage.local.set({ feeds });
    // Notify popup/sidepanel
    chrome.runtime.sendMessage({ action: 'feeds-updated', feeds });
  }

  async saveArticles(articles) {
    await chrome.storage.local.set({ articles });
    chrome.runtime.sendMessage({ action: 'articles-updated', articles });
  }

  // Sync status
  getSyncStatus() {
    return {
      inProgress: this.syncInProgress,
      lastSync: this.lastSyncTime,
      method: this.webrtcSync?.isConnected ? 'webrtc' : 'none'
    };
  }
}

// Export singleton instance
const syncManager = new SyncManager();

// Handle messages from popup/content scripts
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  switch (request.action) {
    case 'start-webrtc-sync':
      syncManager.startWebRTCSync()
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'connect-webrtc':
      syncManager.connectWebRTC(request.data)
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'export-sync':
      syncManager.exportToFile()
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'import-sync':
      syncManager.importFromFile(request.fileContent)
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'get-sync-status':
      sendResponse(syncManager.getSyncStatus());
      break;
  }
});

// Export for use in background.js
if (typeof module !== 'undefined') {
  module.exports = { syncManager };
}