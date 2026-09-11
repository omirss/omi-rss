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

  // Resolves when the transaction DURABLY commits, rejects on abort —
  // request.onsuccess fires before commit, so "resolved = durable" needs
  // this on every write path.
  txDone(tx) {
    return new Promise((resolve, reject) => {
      tx.addEventListener('complete', () => resolve(), { once: true });
      tx.addEventListener('abort', () => reject(tx.error || new Error('transaction aborted')), { once: true });
    });
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

    const request = await new Promise((resolve, reject) => {
      const request = store.add(feed);
      request.onsuccess = () => resolve(request);
      request.onerror = () => reject(request.error);
    });
    await this.txDone(tx);
    return request.result;
  }

  async updateFeed(id, updates) {
    const tx = await this.transaction(['feeds'], 'readwrite');
    const store = tx.objectStore('feeds');

    // Get existing feed
    const getRequest = store.get(id);

    const updated = await new Promise((resolve, reject) => {
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
    await this.txDone(tx);
    return updated;
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

  // Alias used by the side panel
  async init() {
    await this.ensureReady();
  }

  // Save a single feed (upsert by provided id/url)
  async saveFeed(feedData) {
    const existing = feedData.url ? await this.getFeedByUrl(feedData.url) : null;
    if (existing) {
      return this.updateFeed(existing.id, feedData);
    }
    return this.addFeed(feedData);
  }

  // Save a standalone article (saved pages, notes)
  async saveArticle(article) {
    const tx = await this.transaction(['articles'], 'readwrite');
    const store = tx.objectStore('articles');

    const articleData = {
      isRead: false,
      isStarred: false,
      savedAt: new Date().toISOString(),
      ...article
    };

    return new Promise((resolve, reject) => {
      const request = store.put(articleData);
      request.onsuccess = () => {
        articleData.id = articleData.id !== undefined ? articleData.id : request.result;
        resolve(articleData);
      };
      request.onerror = () => reject(request.error);
    });
  }

  // Get a single article by id
  async getArticle(id) {
    const tx = await this.transaction(['articles'], 'readonly');
    const store = tx.objectStore('articles');

    return new Promise((resolve, reject) => {
      const request = store.get(id);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  // Generic article update
  async updateArticle(id, updates) {
    const tx = await this.transaction(['articles'], 'readwrite');
    const store = tx.objectStore('articles');

    const updated = await new Promise((resolve, reject) => {
      const getRequest = store.get(id);
      getRequest.onsuccess = () => {
        const article = getRequest.result;
        if (!article) {
          reject(new Error('Article not found'));
          return;
        }
        const putRequest = store.put({ ...article, ...updates });
        putRequest.onsuccess = () => resolve({ ...article, ...updates });
        putRequest.onerror = () => reject(putRequest.error);
      };
      getRequest.onerror = () => reject(getRequest.error);
    });
    await this.txDone(tx);
    return updated;
  }

  async getAllArticles() {
    return this.getArticles({ limit: 10000 });
  }

  async getArticlesByFeed(feedId) {
    return this.getArticles({ feedId, limit: 10000 });
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
        // Awaited: an unnoticed failure here would silently desync the
        // unread count from the stored articles.
        await new Promise((resolve, reject) => {
          const request = feedStore.put(feed);
          request.onsuccess = () => resolve();
          request.onerror = () => reject(request.error);
        });
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
        // Awaited: an unnoticed failure here would silently desync the
        // unread count from the stored articles.
        await new Promise((resolve, reject) => {
          const request = feedStore.put(feed);
          request.onsuccess = () => resolve();
          request.onerror = () => reject(request.error);
        });
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
    await this.txDone(tx);

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

    const request = await new Promise((resolve, reject) => {
      const request = store.add(folder);
      request.onsuccess = () => {
        folder.id = request.result;
        resolve(request);
      };
      request.onerror = () => reject(request.error);
    });
    await this.txDone(tx);
    return folder;
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

    await new Promise((resolve, reject) => {
      const request = store.put({ key, value, updatedAt: new Date().toISOString() });
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });
    await this.txDone(tx);
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

  // Export all data for backup. ONE readonly transaction over every store
  // so the snapshot is consistent (a concurrent refresh can no longer tear
  // it), with no article cap — the old 10k limit silently truncated large
  // libraries into apparently-successful backups — and syncMetadata is
  // included.
  async exportAllData() {
    await this.ensureReady();

    const storeNames = ['feeds', 'articles', 'folders', 'settings', 'syncMetadata', 'statistics'];

    return new Promise((resolve, reject) => {
      const tx = this.db.transaction(storeNames, 'readonly');
      const results = {};

      for (const name of storeNames) {
        const request = tx.objectStore(name).getAll();
        request.onsuccess = () => {
          results[name] = request.result || [];
        };
        request.onerror = () => {
          reject(request.error);
        };
      }

      tx.oncomplete = () => {
        const settings = {};
        for (const row of results.settings || []) {
          settings[row.key] = row.value;
        }
        resolve({
          version: this.dbVersion,
          exportedAt: new Date().toISOString(),
          feeds: results.feeds || [],
          articles: results.articles || [],
          folders: results.folders || [],
          settings,
          syncMetadata: results.syncMetadata || [],
          statistics: results.statistics || []
        });
      };
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error || new Error('export aborted'));
    });
  }

  // Import data from backup. The whole backup is validated BEFORE any
  // store is touched, then every store is cleared and re-added with the
  // ORIGINAL ids and read/star flags in ONE readwrite transaction — an
  // abort restores the previous data instead of leaving a half-applied
  // import over a wiped library.
  async importData(data) {
    if (!data || data.version !== this.dbVersion) {
      throw new Error('Invalid or incompatible data format');
    }

    const feeds = Array.isArray(data.feeds) ? data.feeds : null;
    const articles = Array.isArray(data.articles) ? data.articles : null;
    if (!feeds || !articles) {
      throw new Error('Backup is missing feeds or articles');
    }
    const folders = Array.isArray(data.folders) ? data.folders : [];
    const settings = (data.settings && typeof data.settings === 'object' && !Array.isArray(data.settings))
      ? data.settings
      : {};
    const statistics = Array.isArray(data.statistics) ? data.statistics : [];
    const syncMetadata = Array.isArray(data.syncMetadata) ? data.syncMetadata : [];

    const uniqueIds = (rows, label) => {
      const seen = new Set();
      for (const row of rows) {
        if (!row || row.id === undefined) {
          throw new Error(`${label} row is missing an id`);
        }
        if (seen.has(row.id)) {
          throw new Error(`${label} contains duplicate id ${row.id}`);
        }
        seen.add(row.id);
      }
      return seen;
    };

    const feedIds = uniqueIds(feeds, 'feeds');
    uniqueIds(articles, 'articles');
    const folderIds = uniqueIds(folders, 'folders');
    for (const folder of folders) {
      if (folder.parentId !== null && folder.parentId !== undefined && !folderIds.has(folder.parentId)) {
        throw new Error(`folder ${folder.id} references an unknown parent folder`);
      }
    }
    for (const feed of feeds) {
      if (feed.folderId !== null && feed.folderId !== undefined && !folderIds.has(feed.folderId)) {
        throw new Error(`feed ${feed.id} references an unknown folder`);
      }
    }
    for (const article of articles) {
      if (article.feedId === undefined || article.feedId === null || !feedIds.has(article.feedId)) {
        throw new Error(`article ${article.id} references an unknown feed`);
      }
    }

    await this.ensureReady();

    const storeNames = ['feeds', 'articles', 'folders', 'settings', 'syncMetadata', 'statistics'];

    await new Promise((resolve, reject) => {
      const tx = this.db.transaction(storeNames, 'readwrite');
      for (const name of storeNames) {
        tx.objectStore(name).clear();
      }

      const puts = [];
      for (const folder of folders) puts.push(tx.objectStore('folders').put(folder));
      for (const feed of feeds) puts.push(tx.objectStore('feeds').put(feed));
      for (const article of articles) puts.push(tx.objectStore('articles').put(article));
      for (const [key, value] of Object.entries(settings)) {
        puts.push(tx.objectStore('settings').put({ key, value, updatedAt: new Date().toISOString() }));
      }
      for (const row of syncMetadata) puts.push(tx.objectStore('syncMetadata').put(row));
      for (const row of statistics) puts.push(tx.objectStore('statistics').put(row));

      let failure = null;
      for (const put of puts) {
        put.onerror = () => {
          failure = failure || put.error;
          tx.abort();
        };
      }
      tx.oncomplete = () => {
        if (failure) {
          reject(failure);
        } else {
          resolve(true);
        }
      };
      tx.onerror = () => reject(tx.error || failure || new Error('import failed'));
      tx.onabort = () => reject(tx.error || failure || new Error('import aborted - previous data retained'));
    });

    return true;
  }
}

// Export singleton instance
const storageService = new StorageService();