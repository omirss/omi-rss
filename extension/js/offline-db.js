// IndexedDB management for offline storage

const DB_NAME = 'OmiRSSOffline';
const DB_VERSION = 1;
const STORES = {
  ARTICLES: 'articles',
  FEEDS: 'feeds',
  SYNC_QUEUE: 'sync_queue'
};

class OfflineDatabase {
  constructor() {
    this.db = null;
  }

  // Initialize database
  async init() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);

      request.onerror = () => reject(request.error);
      request.onsuccess = () => {
        this.db = request.result;
        resolve(this.db);
      };

      request.onupgradeneeded = (event) => {
        const db = event.target.result;

        // Articles store
        if (!db.objectStoreNames.contains(STORES.ARTICLES)) {
          const articlesStore = db.createObjectStore(STORES.ARTICLES, { 
            keyPath: 'id',
            autoIncrement: true 
          });
          articlesStore.createIndex('url', 'url', { unique: true });
          articlesStore.createIndex('feedId', 'feedId', { unique: false });
          articlesStore.createIndex('savedAt', 'savedAt', { unique: false });
          articlesStore.createIndex('isRead', 'isRead', { unique: false });
          articlesStore.createIndex('syncStatus', 'syncStatus', { unique: false });
        }

        // Feeds store
        if (!db.objectStoreNames.contains(STORES.FEEDS)) {
          const feedsStore = db.createObjectStore(STORES.FEEDS, { 
            keyPath: 'id',
            autoIncrement: true 
          });
          feedsStore.createIndex('url', 'url', { unique: true });
          feedsStore.createIndex('syncStatus', 'syncStatus', { unique: false });
        }

        // Sync queue store
        if (!db.objectStoreNames.contains(STORES.SYNC_QUEUE)) {
          const syncStore = db.createObjectStore(STORES.SYNC_QUEUE, { 
            keyPath: 'id',
            autoIncrement: true 
          });
          syncStore.createIndex('action', 'action', { unique: false });
          syncStore.createIndex('timestamp', 'timestamp', { unique: false });
          syncStore.createIndex('status', 'status', { unique: false });
        }
      };
    });
  }

  // Ensure database is open
  async ensureOpen() {
    if (!this.db) {
      await this.init();
    }
  }

  // Save article
  async saveArticle(article) {
    await this.ensureOpen();
    
    const tx = this.db.transaction([STORES.ARTICLES], 'readwrite');
    const store = tx.objectStore(STORES.ARTICLES);
    
    const articleData = {
      ...article,
      savedAt: new Date().toISOString(),
      syncStatus: 'pending',
      isRead: false,
      isBookmarked: false,
      tags: [],
      notes: '',
      readingProgress: 0,
      lastReadAt: null
    };

    // Check if article already exists
    const existingIndex = store.index('url');
    const existing = await this.getByIndex(existingIndex, article.url);
    
    if (existing) {
      // Update existing article
      articleData.id = existing.id;
      articleData.savedAt = existing.savedAt; // Keep original save date
    }

    return new Promise((resolve, reject) => {
      const request = store.put(articleData);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  // Get article by URL
  async getArticleByUrl(url) {
    await this.ensureOpen();
    
    const tx = this.db.transaction([STORES.ARTICLES], 'readonly');
    const store = tx.objectStore(STORES.ARTICLES);
    const index = store.index('url');
    
    return this.getByIndex(index, url);
  }

  // Get all articles
  async getAllArticles(options = {}) {
    await this.ensureOpen();
    
    const tx = this.db.transaction([STORES.ARTICLES], 'readonly');
    const store = tx.objectStore(STORES.ARTICLES);
    
    return new Promise((resolve, reject) => {
      const articles = [];
      let request;

      if (options.feedId) {
        const index = store.index('feedId');
        request = index.openCursor(IDBKeyRange.only(options.feedId));
      } else if (options.isRead !== undefined) {
        const index = store.index('isRead');
        request = index.openCursor(IDBKeyRange.only(options.isRead));
      } else {
        request = store.openCursor();
      }

      request.onsuccess = (event) => {
        const cursor = event.target.result;
        if (cursor) {
          articles.push(cursor.value);
          cursor.continue();
        } else {
          // Sort by savedAt date, newest first
          articles.sort((a, b) => new Date(b.savedAt) - new Date(a.savedAt));
          
          // Apply limit if specified
          if (options.limit) {
            resolve(articles.slice(0, options.limit));
          } else {
            resolve(articles);
          }
        }
      };

      request.onerror = () => reject(request.error);
    });
  }

  // Update article
  async updateArticle(id, updates) {
    await this.ensureOpen();
    
    const tx = this.db.transaction([STORES.ARTICLES], 'readwrite');
    const store = tx.objectStore(STORES.ARTICLES);
    
    return new Promise(async (resolve, reject) => {
      const getRequest = store.get(id);
      
      getRequest.onsuccess = () => {
        const article = getRequest.result;
        if (!article) {
          reject(new Error('Article not found'));
          return;
        }

        const updated = { ...article, ...updates };
        const putRequest = store.put(updated);
        
        putRequest.onsuccess = () => resolve(updated);
        putRequest.onerror = () => reject(putRequest.error);
      };
      
      getRequest.onerror = () => reject(getRequest.error);
    });
  }

  // Delete article
  async deleteArticle(id) {
    await this.ensureOpen();
    
    const tx = this.db.transaction([STORES.ARTICLES], 'readwrite');
    const store = tx.objectStore(STORES.ARTICLES);
    
    return new Promise((resolve, reject) => {
      const request = store.delete(id);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });
  }

  // Save feed
  async saveFeed(feed) {
    await this.ensureOpen();
    
    const tx = this.db.transaction([STORES.FEEDS], 'readwrite');
    const store = tx.objectStore(STORES.FEEDS);
    
    const feedData = {
      ...feed,
      subscribedAt: new Date().toISOString(),
      syncStatus: 'pending',
      lastFetchedAt: null,
      articleCount: 0
    };

    return new Promise((resolve, reject) => {
      const request = store.put(feedData);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  // Get all feeds
  async getAllFeeds() {
    await this.ensureOpen();
    
    const tx = this.db.transaction([STORES.FEEDS], 'readonly');
    const store = tx.objectStore(STORES.FEEDS);
    
    return new Promise((resolve, reject) => {
      const request = store.getAll();
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  // Add to sync queue
  async addToSyncQueue(action, data) {
    await this.ensureOpen();
    
    const tx = this.db.transaction([STORES.SYNC_QUEUE], 'readwrite');
    const store = tx.objectStore(STORES.SYNC_QUEUE);
    
    const queueItem = {
      action,
      data,
      timestamp: new Date().toISOString(),
      status: 'pending',
      attempts: 0,
      lastAttempt: null,
      error: null
    };

    return new Promise((resolve, reject) => {
      const request = store.add(queueItem);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  // Get pending sync items
  async getPendingSyncItems() {
    await this.ensureOpen();
    
    const tx = this.db.transaction([STORES.SYNC_QUEUE], 'readonly');
    const store = tx.objectStore(STORES.SYNC_QUEUE);
    const index = store.index('status');
    
    return new Promise((resolve, reject) => {
      const items = [];
      const request = index.openCursor(IDBKeyRange.only('pending'));
      
      request.onsuccess = (event) => {
        const cursor = event.target.result;
        if (cursor) {
          items.push(cursor.value);
          cursor.continue();
        } else {
          // Sort by timestamp, oldest first
          items.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
          resolve(items);
        }
      };
      
      request.onerror = () => reject(request.error);
    });
  }

  // Update sync queue item
  async updateSyncItem(id, updates) {
    await this.ensureOpen();
    
    const tx = this.db.transaction([STORES.SYNC_QUEUE], 'readwrite');
    const store = tx.objectStore(STORES.SYNC_QUEUE);
    
    return new Promise(async (resolve, reject) => {
      const getRequest = store.get(id);
      
      getRequest.onsuccess = () => {
        const item = getRequest.result;
        if (!item) {
          reject(new Error('Sync item not found'));
          return;
        }

        const updated = { ...item, ...updates };
        const putRequest = store.put(updated);
        
        putRequest.onsuccess = () => resolve(updated);
        putRequest.onerror = () => reject(putRequest.error);
      };
      
      getRequest.onerror = () => reject(getRequest.error);
    });
  }

  // Clear old sync items
  async clearOldSyncItems(daysToKeep = 7) {
    await this.ensureOpen();
    
    const tx = this.db.transaction([STORES.SYNC_QUEUE], 'readwrite');
    const store = tx.objectStore(STORES.SYNC_QUEUE);
    const index = store.index('timestamp');
    
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - daysToKeep);
    
    return new Promise((resolve, reject) => {
      let deletedCount = 0;
      const request = index.openCursor(IDBKeyRange.upperBound(cutoffDate.toISOString()));
      
      request.onsuccess = (event) => {
        const cursor = event.target.result;
        if (cursor) {
          cursor.delete();
          deletedCount++;
          cursor.continue();
        } else {
          resolve(deletedCount);
        }
      };
      
      request.onerror = () => reject(request.error);
    });
  }

  // Get storage info
  async getStorageInfo() {
    if (!navigator.storage?.estimate) {
      return { usage: 0, quota: 0, percent: 0 };
    }

    const estimate = await navigator.storage.estimate();
    const usage = estimate.usage || 0;
    const quota = estimate.quota || 0;
    const percent = quota > 0 ? (usage / quota) * 100 : 0;

    return {
      usage,
      quota,
      percent,
      usageMB: (usage / 1024 / 1024).toFixed(2),
      quotaMB: (quota / 1024 / 1024).toFixed(2)
    };
  }

  // Search articles
  async searchArticles(query) {
    await this.ensureOpen();
    
    const articles = await this.getAllArticles();
    const lowerQuery = query.toLowerCase();
    
    return articles.filter(article => {
      const searchableText = `${article.title} ${article.content} ${article.author || ''} ${article.tags?.join(' ') || ''}`.toLowerCase();
      return searchableText.includes(lowerQuery);
    });
  }

  // Export data
  async exportData() {
    await this.ensureOpen();
    
    const [articles, feeds, syncQueue] = await Promise.all([
      this.getAllArticles(),
      this.getAllFeeds(),
      this.getPendingSyncItems()
    ]);

    return {
      version: DB_VERSION,
      exportedAt: new Date().toISOString(),
      articles,
      feeds,
      syncQueue
    };
  }

  // Import data
  async importData(data) {
    await this.ensureOpen();
    
    const tx = this.db.transaction([STORES.ARTICLES, STORES.FEEDS, STORES.SYNC_QUEUE], 'readwrite');
    
    const promises = [];

    // Import articles
    if (data.articles?.length) {
      const articleStore = tx.objectStore(STORES.ARTICLES);
      data.articles.forEach(article => {
        delete article.id; // Let IndexedDB assign new IDs
        promises.push(articleStore.add(article));
      });
    }

    // Import feeds
    if (data.feeds?.length) {
      const feedStore = tx.objectStore(STORES.FEEDS);
      data.feeds.forEach(feed => {
        delete feed.id;
        promises.push(feedStore.add(feed));
      });
    }

    // Import sync queue
    if (data.syncQueue?.length) {
      const syncStore = tx.objectStore(STORES.SYNC_QUEUE);
      data.syncQueue.forEach(item => {
        delete item.id;
        promises.push(syncStore.add(item));
      });
    }

    return Promise.all(promises);
  }

  // Utility: Get by index
  async getByIndex(index, value) {
    return new Promise((resolve, reject) => {
      const request = index.get(value);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  // Close database
  close() {
    if (this.db) {
      this.db.close();
      this.db = null;
    }
  }
}

// Create singleton instance
const offlineDB = new OfflineDatabase();

// Export for use in other scripts
window.offlineDB = offlineDB;