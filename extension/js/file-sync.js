// Ultra-thin file-based sync implementation
export class FileSync {
  constructor(syncManager) {
    this.syncManager = syncManager;
    this.fileVersion = '1.0';
  }

  // Export all data to file
  async exportData() {
    try {
      // Get all sync data
      const syncData = await this.syncManager.getSyncData();
      
      // Add export metadata
      const exportData = {
        ...syncData,
        exportedAt: new Date().toISOString(),
        fileVersion: this.fileVersion,
        checksum: this.generateChecksum(syncData)
      };

      // Convert to JSON with pretty printing
      const jsonStr = JSON.stringify(exportData, null, 2);
      
      // Create blob
      const blob = new Blob([jsonStr], { type: 'application/json' });
      const url = URL.createObjectURL(blob);

      // Generate filename with timestamp
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, -5);
      const filename = `omi-rss-sync-${timestamp}.json`;

      // Download file - let user choose location (Dropbox, Google Drive, etc)
      const downloadId = await chrome.downloads.download({
        url: url,
        filename: filename,
        saveAs: true
      });

      // Clean up
      setTimeout(() => URL.revokeObjectURL(url), 60000);

      return {
        success: true,
        filename: filename,
        size: blob.size,
        exportedItems: {
          feeds: exportData.data.feeds.length,
          articles: exportData.data.articles.length,
          folders: exportData.data.folders.length
        }
      };
    } catch (error) {
      console.error('Export failed:', error);
      throw new Error(`Export failed: ${error.message}`);
    }
  }

  // Import data from file content
  async importData(fileContent) {
    try {
      // Parse JSON
      const importData = JSON.parse(fileContent);
      
      // Validate file format
      if (!this.validateImportData(importData)) {
        throw new Error('Invalid file format');
      }

      // Check version compatibility
      if (importData.fileVersion !== this.fileVersion) {
        console.warn(`File version mismatch: expected ${this.fileVersion}, got ${importData.fileVersion}`);
        // Could add migration logic here if needed
      }

      // Verify checksum if present
      if (importData.checksum) {
        const dataToCheck = {
          version: importData.version,
          deviceId: importData.deviceId,
          timestamp: importData.timestamp,
          data: importData.data
        };
        const expectedChecksum = this.generateChecksum(dataToCheck);
        if (importData.checksum !== expectedChecksum) {
          console.warn('Checksum mismatch - file may have been modified');
        }
      }

      // Apply the imported data
      await this.syncManager.applySyncData(importData);

      return {
        success: true,
        importedItems: {
          feeds: importData.data.feeds.length,
          articles: importData.data.articles.length,
          folders: importData.data.folders.length
        },
        exportedAt: importData.exportedAt,
        deviceId: importData.deviceId
      };
    } catch (error) {
      console.error('Import failed:', error);
      throw new Error(`Import failed: ${error.message}`);
    }
  }

  // Validate import data structure
  validateImportData(data) {
    // Check required fields
    if (!data || typeof data !== 'object') return false;
    if (!data.version || !data.data) return false;
    if (!data.data.feeds || !Array.isArray(data.data.feeds)) return false;
    if (!data.data.articles || !Array.isArray(data.data.articles)) return false;
    
    // Validate data structure
    const requiredDataFields = ['feeds', 'articles', 'settings', 'readStatus', 'savedArticles', 'folders'];
    for (const field of requiredDataFields) {
      if (!(field in data.data)) return false;
    }

    return true;
  }

  // Generate simple checksum for data integrity
  generateChecksum(data) {
    const str = JSON.stringify(data);
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32-bit integer
    }
    return Math.abs(hash).toString(36);
  }

  // Create automated backup
  async createAutoBackup() {
    try {
      const syncData = await this.syncManager.getSyncData();
      
      // Create compressed backup
      const backupData = {
        ...syncData,
        isAutoBackup: true,
        createdAt: new Date().toISOString()
      };

      const jsonStr = JSON.stringify(backupData);
      
      // Store in chrome.storage.local with rotation
      const backups = await this.getStoredBackups();
      
      // Keep only last 5 backups
      if (backups.length >= 5) {
        backups.shift(); // Remove oldest
      }

      backups.push({
        timestamp: Date.now(),
        size: jsonStr.length,
        data: jsonStr
      });

      await chrome.storage.local.set({ autoBackups: backups });

      return {
        success: true,
        backupCount: backups.length
      };
    } catch (error) {
      console.error('Auto backup failed:', error);
      return { success: false, error: error.message };
    }
  }

  // Get stored backups
  async getStoredBackups() {
    const { autoBackups } = await chrome.storage.local.get('autoBackups');
    return autoBackups || [];
  }

  // Restore from auto backup
  async restoreFromBackup(timestamp) {
    try {
      const backups = await this.getStoredBackups();
      const backup = backups.find(b => b.timestamp === timestamp);
      
      if (!backup) {
        throw new Error('Backup not found');
      }

      const backupData = JSON.parse(backup.data);
      await this.syncManager.applySyncData(backupData);

      return {
        success: true,
        restoredAt: backupData.createdAt
      };
    } catch (error) {
      console.error('Restore failed:', error);
      throw error;
    }
  }

  // Export for OPML format (feeds only)
  async exportOPML() {
    try {
      const { feeds, folders } = await this.syncManager.getSyncData().then(d => d.data);
      
      // Create OPML structure
      const opml = this.createOPMLDocument(feeds, folders);
      
      // Create blob
      const blob = new Blob([opml], { type: 'text/xml' });
      const url = URL.createObjectURL(blob);

      // Download
      const timestamp = new Date().toISOString().slice(0, 10);
      const filename = `omi-rss-feeds-${timestamp}.opml`;

      await chrome.downloads.download({
        url: url,
        filename: filename,
        saveAs: true
      });

      setTimeout(() => URL.revokeObjectURL(url), 60000);

      return {
        success: true,
        filename: filename,
        feedCount: feeds.length
      };
    } catch (error) {
      console.error('OPML export failed:', error);
      throw error;
    }
  }

  // Create OPML document
  createOPMLDocument(feeds, folders) {
    const xmlDoc = document.implementation.createDocument(null, 'opml', null);
    const opml = xmlDoc.documentElement;
    opml.setAttribute('version', '2.0');

    // Head
    const head = xmlDoc.createElement('head');
    head.appendChild(this.createTextElement(xmlDoc, 'title', 'Omi RSS Feeds'));
    head.appendChild(this.createTextElement(xmlDoc, 'dateCreated', new Date().toUTCString()));
    opml.appendChild(head);

    // Body
    const body = xmlDoc.createElement('body');
    
    // Group feeds by folder
    const folderMap = new Map();
    folders.forEach(folder => {
      const outline = xmlDoc.createElement('outline');
      outline.setAttribute('text', folder.name);
      outline.setAttribute('title', folder.name);
      folderMap.set(folder.id, outline);
      body.appendChild(outline);
    });

    // Add uncategorized outline
    const uncategorized = xmlDoc.createElement('outline');
    uncategorized.setAttribute('text', 'Uncategorized');
    uncategorized.setAttribute('title', 'Uncategorized');
    body.appendChild(uncategorized);

    // Add feeds
    feeds.forEach(feed => {
      const outline = xmlDoc.createElement('outline');
      outline.setAttribute('type', 'rss');
      outline.setAttribute('text', feed.title);
      outline.setAttribute('title', feed.title);
      outline.setAttribute('xmlUrl', feed.url);
      outline.setAttribute('htmlUrl', feed.websiteUrl || feed.url);

      const parent = feed.folderId && folderMap.has(feed.folderId) 
        ? folderMap.get(feed.folderId) 
        : uncategorized;
      parent.appendChild(outline);
    });

    opml.appendChild(body);

    // Serialize to string
    const serializer = new XMLSerializer();
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + serializer.serializeToString(xmlDoc);
  }

  createTextElement(doc, name, value) {
    const element = doc.createElement(name);
    element.textContent = value;
    return element;
  }
}

// Handle file import through popup/content script
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === 'import-file-selected') {
    // Handle file selection from popup
    const reader = new FileReader();
    reader.onload = async (e) => {
      try {
        const fileSync = new FileSync(syncManager);
        const result = await fileSync.importData(e.target.result);
        sendResponse(result);
      } catch (error) {
        sendResponse({ error: error.message });
      }
    };
    reader.readAsText(request.file);
    return true; // Keep channel open
  }
});