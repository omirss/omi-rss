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
  //
  // Settings live in chrome.storage.local under the 'settings' key —
  // the same store every settings reader/writer uses (config.js,
  // background.js, popup.js). chrome.storage.sync is NOT read here:
  // nothing in the extension ever wrote it, so merging it was an inert
  // no-op and real settings never traveled.
  async getSyncData() {
    const [snapshot, storedSettings, readStatus, savedArticles, deviceId, modified] = await Promise.all([
      storageService.exportAllData(),
      chrome.storage.local.get('settings'),
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
        settings: (storedSettings && storedSettings.settings) || {},
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
  //
  // Surviving rows are annotated with profile-independent identities so
  // the apply phase never resolves anything through a numeric source
  // id: `_syncFeedUrl` (articles), `_syncOrigin`/`_syncFolderPath`
  // (feeds) and `_syncPath` (folders). Ids are per-profile
  // auto-increment counters, so the SAME numeric id names different
  // rows on each side and any id-keyed map would silently clobber.
  mergeData(local, remote) {
    const merged = {
      version: '1.0',
      deviceId: local.deviceId,
      timestamp: Date.now(),
      data: {}
    };

    // Per-side folder path maps (used to annotate feeds and folders).
    const localPathsById = SyncManager.folderPathMap(local.data.folders);
    const remotePathsById = SyncManager.folderPathMap(remote.data.folders);

    // Feeds by URL. The winner carries its origin side and its
    // folder's NAME PATH (or null for "no folder", undefined for a
    // folderId that side's own folder list cannot resolve).
    const feedByUrl = new Map();
    const considerFeed = (feed, origin, pathsById) => {
      const annotated = {
        ...feed,
        _syncOrigin: origin,
        _syncFolderPath: feed.folderId === null || feed.folderId === undefined
          ? null
          : pathsById.get(feed.folderId)
      };
      const existing = feedByUrl.get(annotated.url);
      if (!existing || String(annotated.updatedAt || '') > String(existing.updatedAt || '')) {
        feedByUrl.set(annotated.url, annotated);
      }
    };
    for (const feed of local.data.feeds) considerFeed(feed, 'local', localPathsById);
    for (const feed of remote.data.feeds) considerFeed(feed, 'remote', remotePathsById);
    merged.data.feeds = Array.from(feedByUrl.values());

    // Articles keyed by (source feed url, guid). Feed ids are
    // per-profile auto-increment counters, so the SAME numeric id can
    // name different feeds on each side: each side's articles must be
    // resolved against THAT side's id->url map. A single shared map
    // would let a colliding remote id silently re-attribute local
    // articles to the wrong feed.
    const feedUrlByLocalId = new Map(local.data.feeds.map(feed => [feed.id, feed.url]));
    const feedUrlByRemoteId = new Map(remote.data.feeds.map(feed => [feed.id, feed.url]));
    const articleMap = new Map();
    const mergeArticle = (article, feedUrlById) => {
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
    for (const article of local.data.articles) mergeArticle(article, feedUrlByLocalId);
    for (const article of remote.data.articles) mergeArticle(article, feedUrlByRemoteId);
    merged.data.articles = Array.from(articleMap.values());

    // Folders by name path. Each surviving folder carries its own
    // side's resolved path (a remote child may hang under a remote
    // parent that was dropped as a path-duplicate; its path is still
    // the full remote path, not just its own name).
    const localPaths = new Set(Array.from(localPathsById.values()));
    const remoteFoldersOnNewPaths = remote.data.folders.filter(folder => !localPaths.has(remotePathsById.get(folder.id)));
    merged.data.folders = [
      ...local.data.folders.map(folder => ({ ...folder, _syncPath: localPathsById.get(folder.id) })),
      ...remoteFoldersOnNewPaths.map(folder => ({ ...folder, _syncPath: remotePathsById.get(folder.id) }))
    ];

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

  // The update patch applied to an EXISTING local feed for a winning
  // merged row. Content columns come from the winner — including the
  // disabled flag (a winning disable/enable must not be dropped) — and
  // the folder assignment: null when the winner has no folder (a
  // removal must propagate), the path-resolved local id when it has
  // one, and "leave untouched" only when the winner's folder is
  // unknown. [folderIdByPath] maps the winner's `_syncFolderPath`
  // (its own side's name path) to a local folder id — never a numeric
  // source id, which is per-profile and collides.
  static feedApplyPatch(feed, folderIdByPath) {
    let folderId;
    if (feed.folderId === null || feed.folderId === undefined) {
      folderId = null;
    } else {
      const mapped = folderIdByPath.get(feed._syncFolderPath);
      folderId = mapped !== undefined ? mapped : undefined;
    }
    return {
      title: feed.title,
      description: feed.description,
      siteUrl: feed.siteUrl,
      favicon: feed.favicon,
      updateInterval: feed.updateInterval,
      disabled: !!feed.disabled,
      ...(folderId !== undefined ? { folderId } : {})
    };
  }

  // Applies a merged bundle: folders by name path (ids remapped), feeds by
  // URL (local counters kept), articles as raw state-preserving upserts
  // keyed by (local feed id, guid) — never addFeed/addArticles, which mint
  // new ids and force isRead/isSaved false. Every identity is resolved by
  // URL or name path (the profile-independent keys the merge phase
  // annotated); numeric source ids are never used as map keys.
  async applyMergedData(merged) {
    await storageService.ensureReady();

    // 1. Folders: identity is the name path. Ensure every merged path
    // exists locally, creating missing ancestors first (a merged remote
    // child can arrive with its parent dropped as a path-duplicate).
    const localFolders = await storageService.getAllFolders();
    const folderIdByPath = new Map();
    for (const [id, path] of SyncManager.folderPathMap(localFolders)) {
      folderIdByPath.set(path, id);
    }

    const mergedFolderById = new Map(merged.data.folders.map(folder => [folder.id, folder]));
    const ensureFolderPath = async (path) => {
      const existing = folderIdByPath.get(path);
      if (existing !== undefined) return existing;
      const segments = path.split('/');
      const name = segments.pop();
      const parentPath = segments.join('/');
      const parentId = parentPath ? await ensureFolderPath(parentPath) : null;
      const created = await storageService.addFolder(name, parentId);
      folderIdByPath.set(path, created.id);
      return created.id;
    };

    // Fallback for callers that hand-build merged data without the
    // merge phase's annotations: resolve the path against the merged
    // folder graph (best-effort; ids may collide in that graph).
    const pathOf = (folder) => typeof folder._syncPath === 'string'
      ? folder._syncPath
      : SyncManager.folderPath(folder, mergedFolderById);
    const mergedPaths = merged.data.folders
      .map(pathOf)
      .filter(path => path.length > 0);
    // Shallow paths first so parents exist before children.
    mergedPaths.sort((a, b) =>
      a.split('/').length - b.split('/').length || (a < b ? -1 : a > b ? 1 : 0));
    for (const path of mergedPaths) {
      await ensureFolderPath(path);
    }

    // 2. Feeds: upsert by URL — merged content columns (including the
    // disabled flag and folder assignment/removal), local counters.
    const feedIdByUrl = new Map();
    for (const feed of merged.data.feeds) {
      const existing = feed.url ? await storageService.getFeedByUrl(feed.url).catch(() => null) : null;
      const patch = SyncManager.feedApplyPatch(feed, folderIdByPath);
      if (existing) {
        await storageService.updateFeed(existing.id, patch);
        feedIdByUrl.set(feed.url, existing.id);
      } else {
        const newId = await storageService.addFeed({
          url: feed.url,
          title: feed.title,
          description: feed.description,
          siteUrl: feed.siteUrl,
          favicon: feed.favicon,
          updateInterval: feed.updateInterval,
          disabled: !!feed.disabled,
          folderId: patch.folderId !== undefined ? patch.folderId : null
        });
        feedIdByUrl.set(feed.url, newId);
      }
    }

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
        // Resolve through the merge annotation only: the source
        // feedId is a per-profile auto-increment id and cannot be
        // mapped safely (colliding ids would re-attribute articles).
        const feedId = feedIdByUrl.get(article._syncFeedUrl);
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

    // 4. chrome.storage pieces. Settings go back to the store the
    // extension actually reads (chrome.storage.local under the
    // 'settings' key), so a winning remote settings merge is live
    // immediately.
    await Promise.all([
      chrome.storage.local.set({ readArticles: merged.data.readStatus }),
      chrome.storage.local.set({ savedArticles: merged.data.savedArticles })
    ]);
    if (merged.settingsFromRemote) {
      // An empty winning settings object carries nothing to apply —
      // legacy exports written while settings sync was inert carry
      // exactly that, and applying it would blank real local settings.
      const settings = merged.data.settings;
      if (settings && typeof settings === 'object' &&
          Object.keys(settings).length > 0) {
        await chrome.storage.local.set({ settings });
        await chrome.storage.local.set({ settingsModifiedAt: Date.now() });
      }
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
