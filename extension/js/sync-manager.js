// Ultra-thin sync manager for Omi RSS browser extension
class SyncManager {
  constructor() {
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

  // One consistent IndexedDB snapshot (via exportAllData — storage failures
  // PROPAGATE so a file export reports failure instead of "successfully"
  // exporting an empty library, and folders come from the real store) plus
  // the chrome.storage pieces. The timestamp is the persisted
  // settingsModifiedAt, not a fresh Date.now(), so an imported file's
  // settings can actually win the merge.
  async getSyncData() {
    const [snapshot, settings, readStatus, savedArticles, deviceId, modified] = await Promise.all([
      storageService.exportAllData(),
      chrome.storage.sync.get(null),
      chrome.storage.local.get('readArticles'),
      chrome.storage.local.get('savedArticles'),
      this.getDeviceId(),
      chrome.storage.local.get('settingsModifiedAt')
    ]);

    return {
      version: '1.0',
      deviceId: deviceId,
      timestamp: (modified && modified.settingsModifiedAt) || 0,
      data: {
        feeds: snapshot.feeds,
        articles: snapshot.articles,
        folders: snapshot.folders,
        settings: settings || {},
        readStatus: (readStatus && readStatus.readArticles) || {},
        savedArticles: (savedArticles && savedArticles.savedArticles) || []
      }
    };
  }

  // Apply sync data from another device/profile
  async applySyncData(remoteData) {
    if (!remoteData || remoteData.version !== '1.0') {
      throw new Error('Invalid sync data format');
    }

    const localData = await this.getSyncData();
    const merged = this.mergeData(localData, remoteData);
    await this.applyMergedData(merged);

    this.lastSyncTime = Date.now();
    await chrome.storage.local.set({ lastSyncTime: this.lastSyncTime });
  }

  // Folder id -> "/"-joined ancestor-name path. Auto-increment ids are
  // per-profile, so cross-profile folder identity is the NAME PATH, never
  // the id.
  static folderPath(folder, byId) {
    const names = [folder.name];
    const seen = new Set([folder.id]);
    let parentId = folder.parentId;
    while (parentId !== null && parentId !== undefined) {
      const parent = byId.get(parentId);
      if (!parent || seen.has(parent.id)) break;
      seen.add(parent.id);
      names.unshift(parent.name);
      parentId = parent.parentId;
    }
    return names.join('/');
  }

  static folderPathMap(folders) {
    const byId = new Map(folders.map(folder => [folder.id, folder]));
    const paths = new Map();
    for (const folder of folders) {
      paths.set(folder.id, SyncManager.folderPath(folder, byId));
    }
    return paths;
  }

  // Pure merge (no chrome/IndexedDB access):
  // - feeds by URL, newer updatedAt wins
  // - articles by (feed URL, guid) — guid uniqueness is per feed, so
  //   same-guid articles from different feeds both survive; content from
  //   the newer row, read/saved flags unioned
  // - folders by name path (local ids win; remote folders on new paths
  //   import)
  // - read status union; saved pages deduped by URL
  // - settings by the REAL persisted settingsModifiedAt timestamps
  mergeData(local, remote) {
    const merged = {
      version: '1.0',
      deviceId: local.deviceId,
      timestamp: Date.now(),
      data: {}
    };

    // Feeds by URL
    const feedByUrl = new Map();
    for (const feed of [...local.data.feeds, ...remote.data.feeds]) {
      const existing = feedByUrl.get(feed.url);
      if (!existing || String(feed.updatedAt || '') > String(existing.updatedAt || '')) {
        feedByUrl.set(feed.url, feed);
      }
    }
    merged.data.feeds = Array.from(feedByUrl.values());

    // Articles keyed by (source feed url, guid)
    const feedUrlById = new Map([
      ...local.data.feeds.map(feed => [feed.id, feed.url]),
      ...remote.data.feeds.map(feed => [feed.id, feed.url])
    ]);
    const articleMap = new Map();
    const mergeArticle = (article) => {
      const feedUrl = feedUrlById.get(article.feedId);
      if (feedUrl === undefined) return; // references a feed neither side has
      const key = `${feedUrl}\u0000${article.guid || article.link || article.id}`;
      const existing = articleMap.get(key);
      if (!existing) {
        articleMap.set(key, { ...article, _syncFeedUrl: feedUrl });
        return;
      }
      const newer = String(article.updatedAt || '') > String(existing.updatedAt || '');
      const base = newer ? article : existing;
      const other = newer ? existing : article;
      articleMap.set(key, {
        ...base,
        isRead: !!(base.isRead || other.isRead),
        isSaved: !!(base.isSaved || other.isSaved),
        readAt: base.readAt || other.readAt || null,
        savedAt: base.savedAt || other.savedAt || null,
        _syncFeedUrl: feedUrl
      });
    };
    for (const article of local.data.articles) mergeArticle(article);
    for (const article of remote.data.articles) mergeArticle(article);
    merged.data.articles = Array.from(articleMap.values());

    // Folders by name path
    const localPaths = new Set(Array.from(SyncManager.folderPathMap(local.data.folders).values()));
    const remotePaths = SyncManager.folderPathMap(remote.data.folders);
    const remoteFoldersOnNewPaths = remote.data.folders.filter(folder => !localPaths.has(remotePaths.get(folder.id)));
    merged.data.folders = [...local.data.folders, ...remoteFoldersOnNewPaths];

    // Read status - union
    merged.data.readStatus = {
      ...local.data.readStatus,
      ...remote.data.readStatus
    };

    // Saved pages - union by URL
    const savedByUrl = new Map();
    for (const item of [...local.data.savedArticles, ...remote.data.savedArticles]) {
      if (!item) continue;
      const key = item.url || item.id;
      if (!savedByUrl.has(key)) {
        savedByUrl.set(key, item);
      }
    }
    merged.data.savedArticles = Array.from(savedByUrl.values());

    // Settings - newer REAL settingsModifiedAt wins
    merged.settingsFromRemote = remote.timestamp > local.timestamp;
    merged.data.settings = merged.settingsFromRemote
      ? remote.data.settings
      : local.data.settings;

    return merged;
  }

  // Applies a merged bundle: folders by name path (ids remapped), feeds by
  // URL (local counters kept), articles as raw state-preserving upserts
  // keyed by (local feed id, guid) — never addFeed/addArticles, which mint
  // new ids and force isRead/isSaved false.
  async applyMergedData(merged) {
    await storageService.ensureReady();

    // 1. Folders: match by path, create the missing ones (parents first).
    const localFolders = await storageService.getAllFolders();
    const folderIdByPath = new Map();
    for (const [id, path] of SyncManager.folderPathMap(localFolders)) {
      folderIdByPath.set(path, id);
    }

    const mergedFolderById = new Map(merged.data.folders.map(folder => [folder.id, folder]));
    const depthOf = (folder, seen = new Set()) => {
      let depth = 0;
      let parentId = folder.parentId;
      while (parentId !== null && parentId !== undefined && !seen.has(parentId)) {
        seen.add(parentId);
        const parent = mergedFolderById.get(parentId);
        if (!parent) break;
        depth++;
        parentId = parent.parentId;
      }
      return depth;
    };
    const sortedFolders = [...merged.data.folders].sort((a, b) => depthOf(a) - depthOf(b));

    const folderIdBySourceId = new Map();
    for (const folder of sortedFolders) {
      const path = SyncManager.folderPath(folder, mergedFolderById);
      const existing = folderIdByPath.get(path);
      if (existing !== undefined) {
        folderIdBySourceId.set(folder.id, existing);
        continue;
      }
      const parentMapped = folder.parentId !== null && folder.parentId !== undefined
        ? folderIdBySourceId.get(folder.parentId)
        : undefined;
      const created = await storageService.addFolder(folder.name, parentMapped !== undefined ? parentMapped : null);
      folderIdByPath.set(path, created.id);
      folderIdBySourceId.set(folder.id, created.id);
    }

    // 2. Feeds: upsert by URL — merged content columns, local counters.
    const feedIdBySourceId = new Map();
    for (const feed of merged.data.feeds) {
      const existing = feed.url ? await storageService.getFeedByUrl(feed.url).catch(() => null) : null;
      const folderId = folderIdBySourceId.get(feed.folderId);
      if (existing) {
        feedIdBySourceId.set(feed.id, existing.id);
        await storageService.updateFeed(existing.id, {
          title: feed.title,
          description: feed.description,
          siteUrl: feed.siteUrl,
          favicon: feed.favicon,
          updateInterval: feed.updateInterval,
          ...(folderId !== undefined ? { folderId } : {})
        });
      } else {
        const newId = await storageService.addFeed({
          url: feed.url,
          title: feed.title,
          description: feed.description,
          siteUrl: feed.siteUrl,
          favicon: feed.favicon,
          updateInterval: feed.updateInterval,
          disabled: !!feed.disabled,
          folderId: folderId !== undefined ? folderId : null
        });
        feedIdBySourceId.set(feed.id, newId);
      }
    }
    const feedIdByUrl = new Map(merged.data.feeds.map(feed => [feed.url, feedIdBySourceId.get(feed.id)]));

    // 3. Articles: raw state-preserving upserts in ONE transaction.
    await new Promise((resolve, reject) => {
      const tx = storageService.db.transaction(['articles'], 'readwrite');
      const store = tx.objectStore('articles');
      const index = store.index('feedId_guid');
      let failure = null;

      const next = (i) => {
        if (failure) {
          tx.abort();
          return;
        }
        if (i >= merged.data.articles.length) {
          return;
        }
        const article = merged.data.articles[i];
        const feedId = article._syncFeedUrl !== undefined
          ? feedIdByUrl.get(article._syncFeedUrl)
          : feedIdBySourceId.get(article.feedId);
        if (feedId === undefined) {
          next(i + 1);
          return;
        }
        const request = index.get([feedId, article.guid]);
        request.onsuccess = () => {
          const existing = request.result;
          const row = { ...article };
          delete row._syncFeedUrl;
          if (existing) {
            // Union the flags again against whatever is stored NOW (the
            // merge snapshot may predate a concurrent local write).
            row.isRead = !!(row.isRead || existing.isRead);
            row.isSaved = !!(row.isSaved || existing.isSaved);
            row.readAt = row.readAt || existing.readAt || null;
            row.savedAt = row.savedAt || existing.savedAt || null;
          }
          const put = store.put({ ...row, feedId, id: existing ? existing.id : undefined });
          put.onerror = () => {
            failure = put.error;
            tx.abort();
          };
          next(i + 1);
        };
        request.onerror = () => {
          failure = request.error;
          tx.abort();
        };
      };
      next(0);

      tx.oncomplete = () => (failure ? reject(failure) : resolve());
      tx.onerror = () => reject(tx.error || failure || new Error('article import failed'));
      tx.onabort = () => reject(tx.error || failure || new Error('article import aborted'));
    });

    // 4. chrome.storage pieces.
    await Promise.all([
      chrome.storage.local.set({ readArticles: merged.data.readStatus }),
      chrome.storage.local.set({ savedArticles: merged.data.savedArticles })
    ]);
    if (merged.settingsFromRemote) {
      await chrome.storage.sync.set(merged.data.settings);
      await chrome.storage.local.set({ settingsModifiedAt: Date.now() });
    }

    chrome.runtime.sendMessage({ action: 'feeds-updated', feeds: merged.data.feeds }).catch(() => {});
    chrome.runtime.sendMessage({ action: 'articles-updated', articles: merged.data.articles }).catch(() => {});
  }

  // File sync methods
  // FileSync is loaded statically (importScripts / background.scripts),
  // because dynamic import() is disallowed in classic service workers.
  getFileSync() {
    if (!this.fileSync) {
      this.fileSync = new FileSync(this);
    }
    return this.fileSync;
  }

  async exportToFile() {
    return this.getFileSync().exportData();
  }

  async importFromFile(fileContent) {
    return this.getFileSync().importData(fileContent);
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

  // Sync status
  getSyncStatus() {
    return {
      inProgress: this.syncInProgress,
      lastSync: this.lastSyncTime,
      method: 'none'
    };
  }
}

// Export singleton instance
const syncManager = new SyncManager();

// Handle messages from popup/content scripts
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  switch (request.action) {
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
  module.exports = { syncManager, SyncManager };
}
