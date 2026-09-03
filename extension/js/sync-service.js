// Sync service for offline/online synchronization with conflict resolution

class SyncService {
  constructor() {
    this.syncing = false;
    this.lastSyncTime = null;
    this.syncInterval = null;
    this.conflictStrategy = 'client-wins'; // 'client-wins', 'server-wins', 'newest-wins', 'manual'
  }

  // Initialize sync service
  async init() {
    // Load last sync time
    const { lastSyncTime, conflictStrategy } = await chrome.storage.local.get(['lastSyncTime', 'conflictStrategy']);
    this.lastSyncTime = lastSyncTime || null;
    this.conflictStrategy = conflictStrategy || 'newest-wins';

    // Set up periodic sync
    this.startPeriodicSync();

    // Listen for online/offline events
    window.addEventListener('online', () => this.onOnline());
    window.addEventListener('offline', () => this.onOffline());

    // Listen for sync messages
    chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
      if (request.action === 'sync-now') {
        this.syncNow().then(sendResponse);
        return true;
      }
    });
  }

  // Start periodic sync
  startPeriodicSync() {
    // Sync every 5 minutes when online
    this.syncInterval = setInterval(() => {
      if (navigator.onLine && !this.syncing) {
        this.syncNow();
      }
    }, 5 * 60 * 1000);
  }

  // Handle coming online
  async onOnline() {
    console.log('Browser is online, starting sync...');
    await this.syncNow();
  }

  // Handle going offline
  onOffline() {
    console.log('Browser is offline');
    if (this.syncing) {
      this.syncing = false;
    }
  }

  // Perform sync now
  async syncNow() {
    if (this.syncing || !navigator.onLine) {
      return { success: false, reason: this.syncing ? 'Already syncing' : 'Offline' };
    }

    this.syncing = true;
    const syncStart = Date.now();
    const results = {
      success: true,
      articlesUploaded: 0,
      articlesDownloaded: 0,
      articlesConflicts: 0,
      feedsSynced: 0,
      errors: []
    };

    try {
      // Get auth token
      const token = await this.getAuthToken();
      if (!token) {
        throw new Error('Not authenticated');
      }

      // 1. Upload pending local changes
      await this.uploadPendingChanges(token, results);

      // 2. Download server changes
      await this.downloadServerChanges(token, results);

      // 3. Resolve conflicts
      await this.resolveConflicts(token, results);

      // 4. Clean up sync queue
      await this.cleanupSyncQueue();

      // Update last sync time
      this.lastSyncTime = new Date().toISOString();
      await chrome.storage.local.set({ lastSyncTime: this.lastSyncTime });

      // Send sync complete notification
      this.notifySyncComplete(results);

    } catch (error) {
      console.error('Sync error:', error);
      results.success = false;
      results.errors.push(error.message);
    } finally {
      this.syncing = false;
    }

    results.duration = Date.now() - syncStart;
    return results;
  }

  // Upload pending local changes
  async uploadPendingChanges(token, results) {
    const pendingItems = await offlineDB.getPendingSyncItems();

    for (const item of pendingItems) {
      try {
        switch (item.action) {
          case 'save-article':
            await this.uploadArticle(token, item.data);
            results.articlesUploaded++;
            break;
          
          case 'update-article':
            await this.updateRemoteArticle(token, item.data);
            results.articlesUploaded++;
            break;
          
          case 'delete-article':
            await this.deleteRemoteArticle(token, item.data.id);
            break;
          
          case 'subscribe-feed':
            await this.subscribeRemoteFeed(token, item.data);
            results.feedsSynced++;
            break;
          
          case 'unsubscribe-feed':
            await this.unsubscribeRemoteFeed(token, item.data.id);
            results.feedsSynced++;
            break;
        }

        // Mark as synced
        await offlineDB.updateSyncItem(item.id, { 
          status: 'synced',
          syncedAt: new Date().toISOString()
        });

      } catch (error) {
        console.error(`Failed to sync item ${item.id}:`, error);
        
        // Update sync item with error
        await offlineDB.updateSyncItem(item.id, {
          status: 'error',
          error: error.message,
          attempts: item.attempts + 1,
          lastAttempt: new Date().toISOString()
        });

        results.errors.push(`${item.action}: ${error.message}`);
      }
    }
  }

  // Download server changes
  async downloadServerChanges(token, results) {
    const API_BASE_URL = await this.getApiBaseUrl();
    
    try {
      // Get changes since last sync
      const params = new URLSearchParams({
        since: this.lastSyncTime || '1970-01-01T00:00:00Z'
      });

      const response = await fetch(`${API_BASE_URL}/sync/changes?${params}`, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });

      if (!response.ok) {
        throw new Error(`Server responded with ${response.status}`);
      }

      const changes = await response.json();

      // Process articles
      if (changes.articles?.length) {
        for (const article of changes.articles) {
          await this.processRemoteArticle(article, results);
        }
      }

      // Process feeds
      if (changes.feeds?.length) {
        for (const feed of changes.feeds) {
          await this.processRemoteFeed(feed, results);
        }
      }

      // Process deletions
      if (changes.deletions?.length) {
        for (const deletion of changes.deletions) {
          await this.processRemoteDeletion(deletion, results);
        }
      }

    } catch (error) {
      console.error('Failed to download server changes:', error);
      results.errors.push(`Download changes: ${error.message}`);
    }
  }

  // Process remote article
  async processRemoteArticle(remoteArticle, results) {
    const localArticle = await offlineDB.getArticleByUrl(remoteArticle.url);

    if (!localArticle) {
      // New article from server
      await offlineDB.saveArticle({
        ...remoteArticle,
        syncStatus: 'synced'
      });
      results.articlesDownloaded++;
    } else {
      // Check for conflicts
      const hasConflict = this.detectConflict(localArticle, remoteArticle);
      
      if (hasConflict) {
        await this.handleArticleConflict(localArticle, remoteArticle);
        results.articlesConflicts++;
      } else if (new Date(remoteArticle.updatedAt) > new Date(localArticle.updatedAt || localArticle.savedAt)) {
        // Remote is newer, update local
        await offlineDB.updateArticle(localArticle.id, {
          ...remoteArticle,
          syncStatus: 'synced'
        });
        results.articlesDownloaded++;
      }
    }
  }

  // Detect conflict between local and remote versions
  detectConflict(local, remote) {
    // Skip if one doesn't have an update time
    if (!local.updatedAt || !remote.updatedAt) {
      return false;
    }

    const localTime = new Date(local.updatedAt);
    const remoteTime = new Date(remote.updatedAt);
    const lastSyncTime = this.lastSyncTime ? new Date(this.lastSyncTime) : new Date(0);

    // Conflict if both changed since last sync
    return localTime > lastSyncTime && remoteTime > lastSyncTime;
  }

  // Handle article conflict
  async handleArticleConflict(local, remote) {
    switch (this.conflictStrategy) {
      case 'client-wins':
        // Keep local version, queue upload
        await offlineDB.addToSyncQueue('update-article', local);
        break;
      
      case 'server-wins':
        // Use remote version
        await offlineDB.updateArticle(local.id, {
          ...remote,
          syncStatus: 'synced'
        });
        break;
      
      case 'newest-wins':
        // Use the most recently modified
        const localTime = new Date(local.updatedAt || local.savedAt);
        const remoteTime = new Date(remote.updatedAt);
        
        if (localTime > remoteTime) {
          await offlineDB.addToSyncQueue('update-article', local);
        } else {
          await offlineDB.updateArticle(local.id, {
            ...remote,
            syncStatus: 'synced'
          });
        }
        break;
      
      case 'manual':
        // Store both versions for manual resolution
        await this.storeConflict(local, remote);
        break;
    }
  }

  // Store conflict for manual resolution
  async storeConflict(local, remote) {
    const conflicts = await chrome.storage.local.get('conflicts') || {};
    const conflictId = `${local.id}_${Date.now()}`;
    
    conflicts[conflictId] = {
      type: 'article',
      local,
      remote,
      detectedAt: new Date().toISOString()
    };

    await chrome.storage.local.set({ conflicts });
    
    // Show notification about conflict
    chrome.notifications.create({
      type: 'basic',
      iconUrl: 'icons/icon-128.png',
      title: 'Sync Conflict',
      message: `Article "${local.title}" has conflicting changes`,
      buttons: [
        { title: 'Keep Local' },
        { title: 'Keep Server' }
      ]
    });
  }

  // Resolve conflicts manually
  async resolveConflict(conflictId, resolution) {
    const { conflicts } = await chrome.storage.local.get('conflicts');
    const conflict = conflicts[conflictId];
    
    if (!conflict) return;

    if (resolution === 'local') {
      await offlineDB.addToSyncQueue('update-article', conflict.local);
    } else {
      await offlineDB.updateArticle(conflict.local.id, {
        ...conflict.remote,
        syncStatus: 'synced'
      });
    }

    // Remove resolved conflict
    delete conflicts[conflictId];
    await chrome.storage.local.set({ conflicts });
  }

  // Upload article to server
  async uploadArticle(token, article) {
    const API_BASE_URL = await this.getApiBaseUrl();
    
    const response = await fetch(`${API_BASE_URL}/articles`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(article)
    });

    if (!response.ok) {
      throw new Error(`Failed to upload article: ${response.status}`);
    }

    const serverArticle = await response.json();
    
    // Update local article with server ID
    await offlineDB.updateArticle(article.id, {
      serverId: serverArticle.id,
      syncStatus: 'synced'
    });
  }

  // Get auth token
  async getAuthToken() {
    const { authToken } = await chrome.storage.local.get('authToken');
    return authToken;
  }

  // Get API base URL
  async getApiBaseUrl() {
    const { apiBaseUrl } = await chrome.storage.local.get('apiBaseUrl');
    return apiBaseUrl || 'http://localhost:8080/api';
  }

  // Clean up old sync queue items
  async cleanupSyncQueue() {
    // Remove synced items older than 7 days
    await offlineDB.clearOldSyncItems(7);
  }

  // Notify sync complete
  notifySyncComplete(results) {
    if (!results.success) {
      chrome.notifications.create({
        type: 'basic',
        iconUrl: 'icons/icon-128.png',
        title: 'Sync Failed',
        message: `Sync encountered errors: ${results.errors.join(', ')}`
      });
    } else if (results.articlesUploaded > 0 || results.articlesDownloaded > 0) {
      chrome.notifications.create({
        type: 'basic',
        iconUrl: 'icons/icon-128.png',
        title: 'Sync Complete',
        message: `Uploaded: ${results.articlesUploaded}, Downloaded: ${results.articlesDownloaded}, Conflicts: ${results.articlesConflicts}`
      });
    }
  }

  // Get sync status
  async getSyncStatus() {
    const pendingItems = await offlineDB.getPendingSyncItems();
    const { conflicts } = await chrome.storage.local.get('conflicts');
    
    return {
      syncing: this.syncing,
      lastSyncTime: this.lastSyncTime,
      pendingItems: pendingItems.length,
      conflicts: Object.keys(conflicts || {}).length,
      online: navigator.onLine
    };
  }

  // Export data for backup
  async exportBackup() {
    const data = await offlineDB.exportData();
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    
    const filename = `omi-rss-backup-${new Date().toISOString().split('T')[0]}.json`;
    
    chrome.downloads.download({
      url,
      filename,
      saveAs: true
    });
  }

  // Import backup data
  async importBackup(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      
      reader.onload = async (e) => {
        try {
          const data = JSON.parse(e.target.result);
          await offlineDB.importData(data);
          resolve({ success: true, message: 'Backup imported successfully' });
        } catch (error) {
          reject(error);
        }
      };
      
      reader.onerror = () => reject(new Error('Failed to read file'));
      reader.readAsText(file);
    });
  }
}

// Create singleton instance
const syncService = new SyncService();

// Export for use in other scripts
window.syncService = syncService;