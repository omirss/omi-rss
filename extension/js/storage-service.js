// IndexedDB Storage Service for Browser Extension
class StorageService {
  constructor() {
    this.dbName = 'OmiRSSData';
    this.dbVersion = 1;
    this.db = null;
    this.initPromise = this.initDatabase();
  }

  // Initialize IndexedDB
  async initDatabase() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(this.dbName, this.dbVersion);

      request.onerror = () => {
        console.error('Failed to open IndexedDB:', request.error);
        reject(request.error);
      };

      request.onsuccess = () => {
        this.db = request.result;
        console.log('IndexedDB initialized successfully');
        resolve();
      };

      request.onupgradeneeded = (event) => {
        const db = event.target.result;
        
        // Create object stores
        this.createObjectStores(db);
      };
    });
  }

  // Create object stores and indexes
  createObjectStores(db) {
    // Feeds store
    if (!db.objectStoreNames.contains('feeds')) {
      const feedStore = db.createObjectStore('feeds', { keyPath: 'id', autoIncrement: true });
      feedStore.createIndex('url', 'url', { unique: true });
      feedStore.createIndex('folderId', 'folderId', { unique: false });
      feedStore.createIndex('lastUpdated', 'lastUpdated', { unique: false });
    }

    // Articles store
    if (!db.objectStoreNames.contains('articles')) {
      const articleStore = db.createObjectStore('articles', { keyPath: 'id', autoIncrement: true });
      articleStore.createIndex('feedId', 'feedId', { unique: false });
      articleStore.createIndex('guid', 'guid', { unique: false });
      articleStore.createIndex('feedId_guid', ['feedId', 'guid'], { unique: true });
      articleStore.createIndex('publishedAt', 'publishedAt', { unique: false });
      articleStore.createIndex('isRead', 'isRead', { unique: false });
      articleStore.createIndex('isSaved', 'isSaved', { unique: false });
    }

    // Folders store
    if (!db.objectStoreNames.contains('folders')) {
      const folderStore = db.createObjectStore('folders', { keyPath: 'id', autoIncrement: true });
      folderStore.createIndex('name', 'name', { unique: false });
      folderStore.createIndex('parentId', 'parentId', { unique: false });
    }

    // Settings store
    if (!db.objectStoreNames.contains('settings')) {
      db.createObjectStore('settings', { keyPath: 'key' });
    }

    // Sync metadata store
    if (!db.objectStoreNames.contains('syncMetadata')) {
      db.createObjectStore('syncMetadata', { keyPath: 'key' });
    }

    // Reading statistics store
    if (!db.objectStoreNames.contains('statistics')) {
      const statsStore = db.createObjectStore('statistics', { keyPath: 'id', autoIncrement: true });
      statsStore.createIndex('date', 'date', { unique: false });
      statsStore.createIndex('feedId', 'feedId', { unique: false });
    }
  }

  // Ensure database is ready
  async ensureReady() {
    if (!this.db) {
      await this.initPromise;
    }
  }

  // Generic transaction helper
  async transaction(storeNames, mode = 'readonly') {
    await this.ensureReady();
    return this.db.transaction(storeNames, mode);
  }

  // Feed operations
  async addFeed(feedData) {
    const tx = await this.transaction(['feeds'], 'readwrite');
    const store = tx.objectStore('feeds');
    
    // Prepare feed data
    const feed = {
      ...feedData,
      createdAt: new Date().toISOString(),
      lastUpdated: new Date().toISOString(),
      unreadCount: 0,
      errorCount: 0,
      updateInterval: feedData.updateInterval || 3600000 // 1 hour default
    };

    return new Promise((resolve, reject) => {
      const request = store.add(feed);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  async updateFeed(id, updates) {
    const tx = await this.transaction(['feeds'], 'readwrite');
    const store = tx.objectStore('feeds');
    
    // Get existing feed
    const getRequest = store.get(id);
    
    return new Promise((resolve, reject) => {
      getRequest.onsuccess = () => {
        const feed = getRequest.result;
        if (!feed) {
          reject(new Error('Feed not found'));
          return;
        }

        // Update feed
        const updated = { ...feed, ...updates, lastUpdated: new Date().toISOString() };
        const updateRequest = store.put(updated);
        
        updateRequest.onsuccess = () => resolve(updated);
        updateRequest.onerror = () => reject(updateRequest.error);
      };
      
      getRequest.onerror = () => reject(getRequest.error);
    });
  }

  async deleteFeed(id) {
    const tx = await this.transaction(['feeds', 'articles'], 'readwrite');
    
    // Delete feed
    const feedStore = tx.objectStore('feeds');
    await new Promise((resolve, reject) => {
      const request = feedStore.delete(id);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });

    // Delete associated articles
    const articleStore = tx.objectStore('articles');
    const index = articleStore.index('feedId');
    const range = IDBKeyRange.only(id);
    
    return new Promise((resolve, reject) => {
      const request = index.openCursor(range);
      
      request.onsuccess = (event) => {
        const cursor = event.target.result;
        if (cursor) {
          articleStore.delete(cursor.primaryKey);
          cursor.continue();
        } else {
          resolve();
        }
      };
      
      request.onerror = () => reject(request.error);
    });
  }

  async getFeed(id) {
    const tx = await this.transaction(['feeds'], 'readonly');
    const store = tx.objectStore('feeds');
    
    return new Promise((resolve, reject) => {
      const request = store.get(id);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  async getFeedByUrl(url) {
    const tx = await this.transaction(['feeds'], 'readonly');
    const store = tx.objectStore('feeds');
    const index = store.index('url');
    
    return new Promise((resolve, reject) => {
      const request = index.get(url);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  async getAllFeeds() {
    const tx = await this.transaction(['feeds'], 'readonly');
    const store = tx.objectStore('feeds');
    
    return new Promise((resolve, reject) => {
      const request = store.getAll();
      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => reject(request.error);
    });
  }

  // Article operations
  async addArticles(articles, feedId) {
    const tx = await this.transaction(['articles', 'feeds'], 'readwrite');
    const articleStore = tx.objectStore('articles');
    const feedStore = tx.objectStore('feeds');
    
    const addedArticles = [];
    let newArticleCount = 0;

    for (const article of articles) {
      // Check if article already exists
      const index = articleStore.index('feedId_guid');
      const key = [feedId, article.guid];
      
      const exists = await new Promise((resolve) => {
        const request = index.get(key);
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => resolve(null);
      });

      if (!exists) {
        // Prepare article data
        const articleData = {
          ...article,
          feedId: feedId,
          isRead: false,
          isSaved: false,
          readAt: null,
          savedAt: null,
          createdAt: new Date().toISOString()
        };

        // Add article
        const id = await new Promise((resolve, reject) => {
          const request = articleStore.add(articleData);
          request.onsuccess = () => resolve(request.result);
          request.onerror = () => reject(request.error);
        });

        articleData.id = id;
        addedArticles.push(articleData);
        newArticleCount++;
      }
    }

    // Update feed unread count
    if (newArticleCount > 0) {
      const feed = await new Promise((resolve) => {
        const request = feedStore.get(feedId);
        request.onsuccess = () => resolve(request.result);
      });

      if (feed) {
        feed.unreadCount = (feed.unreadCount || 0) + newArticleCount;
        feed.lastFetched = new Date().toISOString();
        feedStore.put(feed);
      }
    }

    return addedArticles;
  }

  async getArticles(options = {}) {
    const {
      feedId,
      isRead,
      isSaved,
      limit = 50,
      offset = 0,
      sortBy = 'publishedAt',
      sortOrder = 'desc'
    } = options;

    const tx = await this.transaction(['articles'], 'readonly');
    const store = tx.objectStore('articles');
    
    let articles = [];

    // Get all articles or filtered by feedId
    if (feedId) {
      const index = store.index('feedId');
      const range = IDBKeyRange.only(feedId);
      articles = await this.getFromIndex(index, range);
    } else {
      articles = await new Promise((resolve, reject) => {
        const request = store.getAll();
        request.onsuccess = () => resolve(request.result || []);
        request.onerror = () => reject(request.error);
      });
    }

    // Apply filters
    if (isRead !== undefined) {
      articles = articles.filter(a => a.isRead === isRead);
    }
    if (isSaved !== undefined) {
      articles = articles.filter(a => a.isSaved === isSaved);
    }

    // Sort articles
    articles.sort((a, b) => {
      const aVal = a[sortBy];
      const bVal = b[sortBy];
      
      if (sortOrder === 'desc') {
        return bVal > aVal ? 1 : -1;
      } else {
        return aVal > bVal ? 1 : -1;
      }
    });

    // Apply pagination
    return articles.slice(offset, offset + limit);
  }

  async markArticleRead(articleId, isRead = true) {
    const tx = await this.transaction(['articles', 'feeds'], 'readwrite');
    const articleStore = tx.objectStore('articles');
    const feedStore = tx.objectStore('feeds');
    
    // Get article
    const article = await new Promise((resolve, reject) => {
      const request = articleStore.get(articleId);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });

    if (!article) {
      throw new Error('Article not found');
    }

    // Update article
    const wasRead = article.isRead;
    article.isRead = isRead;
    article.readAt = isRead ? new Date().toISOString() : null;
    
    await new Promise((resolve, reject) => {
      const request = articleStore.put(article);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });

    // Update feed unread count
    if (wasRead !== isRead) {
      const feed = await new Promise((resolve) => {
        const request = feedStore.get(article.feedId);
        request.onsuccess = () => resolve(request.result);
      });

      if (feed) {
        feed.unreadCount = Math.max(0, (feed.unreadCount || 0) + (isRead ? -1 : 1));
        feedStore.put(feed);
      }
    }

    // Track reading statistics
    if (isRead && !wasRead) {
      await this.trackReadingStatistic(article);
    }

    return article;
  }

  async markArticleSaved(articleId, isSaved = true) {
    const tx = await this.transaction(['articles'], 'readwrite');
    const store = tx.objectStore('articles');
    
    // Get article
    const article = await new Promise((resolve, reject) => {
      const request = store.get(articleId);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });

    if (!article) {
      throw new Error('Article not found');
    }

    // Update article
    article.isSaved = isSaved;
    article.savedAt = isSaved ? new Date().toISOString() : null;
    
    await new Promise((resolve, reject) => {
      const request = store.put(article);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });

    return article;
  }

  async markAllRead(feedId = null) {
    const tx = await this.transaction(['articles', 'feeds'], 'readwrite');
    const articleStore = tx.objectStore('articles');
    const feedStore = tx.objectStore('feeds');
    
    let articles;
    if (feedId) {
      const index = articleStore.index('feedId');
      articles = await this.getFromIndex(index, IDBKeyRange.only(feedId));
    } else {
      articles = await new Promise((resolve) => {
        const request = articleStore.getAll();
        request.onsuccess = () => resolve(request.result || []);
      });
    }

    // Mark articles as read
    const now = new Date().toISOString();
    let count = 0;
    
    for (const article of articles) {
      if (!article.isRead) {
        article.isRead = true;
        article.readAt = now;
        articleStore.put(article);
        count++;
      }
    }

    // Update feed unread counts
    if (feedId) {
      const feed = await new Promise((resolve) => {
        const request = feedStore.get(feedId);
        request.onsuccess = () => resolve(request.result);
      });
      
      if (feed) {
        feed.unreadCount = 0;
        feedStore.put(feed);
      }
    } else {
      // Reset all feeds
      const feeds = await new Promise((resolve) => {
        const request = feedStore.getAll();
        request.onsuccess = () => resolve(request.result || []);
      });
      
      for (const feed of feeds) {
        feed.unreadCount = 0;
        feedStore.put(feed);
      }
    }

    return count;
  }

  // Folder operations
  async addFolder(name, parentId = null) {
    const tx = await this.transaction(['folders'], 'readwrite');
    const store = tx.objectStore('folders');
    
    const folder = {
      name,
      parentId,
      position: 0,
      createdAt: new Date().toISOString()
    };

    return new Promise((resolve, reject) => {
      const request = store.add(folder);
      request.onsuccess = () => {
        folder.id = request.result;
        resolve(folder);
      };
      request.onerror = () => reject(request.error);
    });
  }

  async getAllFolders() {
    const tx = await this.transaction(['folders'], 'readonly');
    const store = tx.objectStore('folders');
    
    return new Promise((resolve, reject) => {
      const request = store.getAll();
      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => reject(request.error);
    });
  }

  // Settings operations
  async getSetting(key, defaultValue = null) {
    const tx = await this.transaction(['settings'], 'readonly');
    const store = tx.objectStore('settings');
    
    return new Promise((resolve) => {
      const request = store.get(key);
      request.onsuccess = () => resolve(request.result?.value ?? defaultValue);
      request.onerror = () => resolve(defaultValue);
    });
  }

  async setSetting(key, value) {
    const tx = await this.transaction(['settings'], 'readwrite');
    const store = tx.objectStore('settings');
    
    return new Promise((resolve, reject) => {
      const request = store.put({ key, value, updatedAt: new Date().toISOString() });
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });
  }

  // Statistics operations
  async trackReadingStatistic(article) {
    const tx = await this.transaction(['statistics'], 'readwrite');
    const store = tx.objectStore('statistics');
    
    const stat = {
      type: 'article_read',
      feedId: article.feedId,
      articleId: article.id,
      date: new Date().toISOString().split('T')[0], // YYYY-MM-DD
      timestamp: new Date().toISOString()
    };

    return new Promise((resolve, reject) => {
      const request = store.add(stat);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });
  }

  async getReadingStatistics(days = 30) {
    const tx = await this.transaction(['statistics'], 'readonly');
    const store = tx.objectStore('statistics');
    
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - days);
    const startDateStr = startDate.toISOString().split('T')[0];
    
    const stats = await new Promise((resolve, reject) => {
      const request = store.getAll();
      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => reject(request.error);
    });

    // Filter by date and aggregate
    const dailyStats = {};
    const feedStats = {};
    
    stats
      .filter(s => s.date >= startDateStr && s.type === 'article_read')
      .forEach(stat => {
        // Daily stats
        dailyStats[stat.date] = (dailyStats[stat.date] || 0) + 1;
        
        // Feed stats
        feedStats[stat.feedId] = (feedStats[stat.feedId] || 0) + 1;
      });

    return {
      daily: dailyStats,
      byFeed: feedStats,
      total: Object.values(dailyStats).reduce((sum, count) => sum + count, 0)
    };
  }

  // Helper to get from index
  async getFromIndex(index, range) {
    const results = [];
    
    return new Promise((resolve, reject) => {
      const request = index.openCursor(range);
      
      request.onsuccess = (event) => {
        const cursor = event.target.result;
        if (cursor) {
          results.push(cursor.value);
          cursor.continue();
        } else {
          resolve(results);
        }
      };
      
      request.onerror = () => reject(request.error);
    });
  }

  // Clear all data (for testing/reset)
  async clearAllData() {
    const tx = await this.transaction(
      ['feeds', 'articles', 'folders', 'settings', 'syncMetadata', 'statistics'],
      'readwrite'
    );
    
    const stores = [
      'feeds', 'articles', 'folders', 'settings', 'syncMetadata', 'statistics'
    ];
    
    for (const storeName of stores) {
      await new Promise((resolve, reject) => {
        const request = tx.objectStore(storeName).clear();
        request.onsuccess = () => resolve();
        request.onerror = () => reject(request.error);
      });
    }
  }

  // Export all data for backup
  async exportAllData() {
    await this.ensureReady();
    
    const data = {
      version: this.dbVersion,
      exportedAt: new Date().toISOString(),
      feeds: await this.getAllFeeds(),
      articles: await this.getArticles({ limit: 10000 }),
      folders: await this.getAllFolders(),
      settings: {},
      statistics: []
    };

    // Get all settings
    const tx = await this.transaction(['settings', 'statistics'], 'readonly');
    
    const settings = await new Promise((resolve) => {
      const request = tx.objectStore('settings').getAll();
      request.onsuccess = () => resolve(request.result || []);
    });
    
    settings.forEach(s => {
      data.settings[s.key] = s.value;
    });

    // Get statistics
    data.statistics = await new Promise((resolve) => {
      const request = tx.objectStore('statistics').getAll();
      request.onsuccess = () => resolve(request.result || []);
    });

    return data;
  }

  // Import data from backup
  async importData(data) {
    if (!data || data.version !== this.dbVersion) {
      throw new Error('Invalid or incompatible data format');
    }

    // Clear existing data first
    await this.clearAllData();

    // Import folders first (for hierarchy)
    if (data.folders) {
      for (const folder of data.folders) {
        await this.addFolder(folder.name, folder.parentId);
      }
    }

    // Import feeds
    if (data.feeds) {
      for (const feed of data.feeds) {
        await this.addFeed(feed);
      }
    }

    // Import articles
    if (data.articles) {
      const articlesByFeed = {};
      data.articles.forEach(article => {
        if (!articlesByFeed[article.feedId]) {
          articlesByFeed[article.feedId] = [];
        }
        articlesByFeed[article.feedId].push(article);
      });

      for (const [feedId, articles] of Object.entries(articlesByFeed)) {
        await this.addArticles(articles, parseInt(feedId));
      }
    }

    // Import settings
    if (data.settings) {
      for (const [key, value] of Object.entries(data.settings)) {
        await this.setSetting(key, value);
      }
    }

    return true;
  }
}

// Export singleton instance
const storageService = new StorageService();