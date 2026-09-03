// Feed Update Scheduler for Browser Extension
class FeedScheduler {
  constructor() {
    this.storageService = new StorageService();
    this.feedParser = new FeedParser();
    this.updateIntervals = new Map(); // feedId -> intervalId
    this.isRunning = false;
    this.defaultUpdateInterval = 3600000; // 1 hour
    this.minUpdateInterval = 300000; // 5 minutes
    this.maxUpdateInterval = 86400000; // 24 hours
  }

  // Start the scheduler
  async start() {
    if (this.isRunning) return;
    
    console.log('Starting feed scheduler...');
    this.isRunning = true;
    
    // Load all feeds and schedule updates
    await this.scheduleAllFeeds();
    
    // Listen for feed changes
    this.setupEventListeners();
    
    // Check for stale feeds on startup
    await this.checkStaleFeeds();
  }

  // Stop the scheduler
  stop() {
    console.log('Stopping feed scheduler...');
    this.isRunning = false;
    
    // Clear all intervals
    for (const [feedId, intervalId] of this.updateIntervals) {
      clearInterval(intervalId);
    }
    this.updateIntervals.clear();
  }

  // Schedule updates for all feeds
  async scheduleAllFeeds() {
    const feeds = await this.storageService.getAllFeeds();
    
    for (const feed of feeds) {
      this.scheduleFeed(feed);
    }
  }

  // Schedule updates for a single feed
  scheduleFeed(feed) {
    // Clear existing interval if any
    if (this.updateIntervals.has(feed.id)) {
      clearInterval(this.updateIntervals.get(feed.id));
    }
    
    // Don't schedule if feed is disabled
    if (feed.disabled) return;
    
    // Get update interval
    const interval = this.getUpdateInterval(feed);
    
    // Schedule the update
    const intervalId = setInterval(async () => {
      await this.updateFeed(feed.id);
    }, interval);
    
    this.updateIntervals.set(feed.id, intervalId);
    
    console.log(`Scheduled feed "${feed.title}" to update every ${interval / 1000 / 60} minutes`);
  }

  // Get update interval for a feed
  getUpdateInterval(feed) {
    let interval = feed.updateInterval || this.defaultUpdateInterval;
    
    // Apply smart scheduling based on feed activity
    if (feed.errorCount > 5) {
      // Reduce frequency for feeds with many errors
      interval = Math.min(interval * 2, this.maxUpdateInterval);
    } else if (feed.lastUpdated) {
      // Adjust based on how often the feed actually updates
      const hoursSinceUpdate = (Date.now() - new Date(feed.lastUpdated).getTime()) / 1000 / 60 / 60;
      
      if (hoursSinceUpdate > 24) {
        // Feed hasn't updated in a day, check less frequently
        interval = Math.min(interval * 1.5, this.maxUpdateInterval);
      } else if (hoursSinceUpdate < 1) {
        // Feed updates frequently, check more often
        interval = Math.max(interval * 0.5, this.minUpdateInterval);
      }
    }
    
    return interval;
  }

  // Update a single feed
  async updateFeed(feedId) {
    try {
      console.log(`Updating feed ${feedId}...`);
      
      const feed = await this.storageService.getFeed(feedId);
      if (!feed || feed.disabled) return;
      
      // Parse the feed
      const result = await this.feedParser.parseFeed(feed.url);
      
      if (result.success) {
        // Update feed metadata
        await this.storageService.updateFeed(feedId, {
          title: result.feed.title,
          description: result.feed.description,
          lastUpdated: new Date().toISOString(),
          errorCount: 0,
          lastError: null
        });
        
        // Add new articles
        const newArticles = await this.storageService.addArticles(result.feed.items, feedId);
        
        // Update unread count
        const unreadCount = (feed.unreadCount || 0) + newArticles.length;
        await this.storageService.updateFeed(feedId, { unreadCount });
        
        // Send notification if new articles
        if (newArticles.length > 0) {
          this.sendNewArticlesNotification(feed, newArticles.length);
        }
        
        // Update badge
        await this.updateBadge();
        
        console.log(`Updated feed "${feed.title}": ${newArticles.length} new articles`);
      } else {
        // Handle error
        await this.storageService.updateFeed(feedId, {
          errorCount: (feed.errorCount || 0) + 1,
          lastError: result.error
        });
        
        console.error(`Failed to update feed "${feed.title}": ${result.error}`);
      }
    } catch (error) {
      console.error(`Error updating feed ${feedId}:`, error);
    }
  }

  // Check for stale feeds that need updating
  async checkStaleFeeds() {
    const feeds = await this.storageService.getAllFeeds();
    const now = Date.now();
    
    for (const feed of feeds) {
      if (feed.disabled) continue;
      
      const lastUpdated = feed.lastUpdated ? new Date(feed.lastUpdated).getTime() : 0;
      const timeSinceUpdate = now - lastUpdated;
      const updateInterval = this.getUpdateInterval(feed);
      
      // If feed is overdue for update, update it now
      if (timeSinceUpdate > updateInterval) {
        console.log(`Feed "${feed.title}" is stale, updating now...`);
        await this.updateFeed(feed.id);
      }
    }
  }

  // Update all feeds manually
  async updateAllFeeds() {
    console.log('Updating all feeds...');
    
    const feeds = await this.storageService.getAllFeeds();
    const results = {
      success: 0,
      failed: 0,
      newArticles: 0
    };
    
    // Update feeds in parallel (max 3 at a time)
    const batchSize = 3;
    for (let i = 0; i < feeds.length; i += batchSize) {
      const batch = feeds.slice(i, i + batchSize);
      
      await Promise.all(batch.map(async (feed) => {
        try {
          const before = await this.storageService.getArticles({ feedId: feed.id });
          await this.updateFeed(feed.id);
          const after = await this.storageService.getArticles({ feedId: feed.id });
          
          const newCount = after.length - before.length;
          results.newArticles += newCount;
          results.success++;
        } catch (error) {
          results.failed++;
        }
      }));
    }
    
    console.log('Update complete:', results);
    return results;
  }

  // Send notification for new articles
  sendNewArticlesNotification(feed, count) {
    if (!chrome.notifications) return;
    
    const title = `New articles in ${feed.title}`;
    const message = count === 1 
      ? '1 new article' 
      : `${count} new articles`;
    
    chrome.notifications.create({
      type: 'basic',
      iconUrl: feed.favicon || '/icons/icon-128.png',
      title: title,
      message: message,
      buttons: [
        { title: 'Read now' }
      ]
    }, (notificationId) => {
      // Store feed ID for click handler
      chrome.storage.local.set({ 
        [`notification_${notificationId}`]: feed.id 
      });
    });
  }

  // Update extension badge with unread count
  async updateBadge() {
    const feeds = await this.storageService.getAllFeeds();
    const totalUnread = feeds.reduce((sum, feed) => sum + (feed.unreadCount || 0), 0);
    
    if (chrome.action) {
      // Manifest V3
      chrome.action.setBadgeText({ 
        text: totalUnread > 0 ? totalUnread.toString() : '' 
      });
      chrome.action.setBadgeBackgroundColor({ 
        color: '#f5576c' 
      });
    } else if (chrome.browserAction) {
      // Manifest V2
      chrome.browserAction.setBadgeText({ 
        text: totalUnread > 0 ? totalUnread.toString() : '' 
      });
      chrome.browserAction.setBadgeBackgroundColor({ 
        color: '#f5576c' 
      });
    }
  }

  // Setup event listeners
  setupEventListeners() {
    // Listen for notification clicks
    if (chrome.notifications) {
      chrome.notifications.onButtonClicked.addListener(async (notificationId, buttonIndex) => {
        if (buttonIndex === 0) { // "Read now" button
          const result = await chrome.storage.local.get([`notification_${notificationId}`]);
          const feedId = result[`notification_${notificationId}`];
          
          if (feedId) {
            // Open feed in new tab
            chrome.tabs.create({
              url: chrome.runtime.getURL(`sidepanel.html#feed/${feedId}`)
            });
            
            // Clean up
            chrome.storage.local.remove([`notification_${notificationId}`]);
          }
        }
        
        chrome.notifications.clear(notificationId);
      });
    }
    
    // Listen for manual refresh requests
    chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
      if (request.action === 'refreshFeed') {
        this.updateFeed(request.feedId).then(() => {
          sendResponse({ success: true });
        }).catch((error) => {
          sendResponse({ success: false, error: error.message });
        });
        return true; // Keep channel open for async response
      }
      
      if (request.action === 'refreshAllFeeds') {
        this.updateAllFeeds().then((results) => {
          sendResponse({ success: true, results });
        }).catch((error) => {
          sendResponse({ success: false, error: error.message });
        });
        return true;
      }
    });
  }

  // Add or update a feed in the scheduler
  async addOrUpdateFeed(feed) {
    // Remove existing schedule if any
    if (this.updateIntervals.has(feed.id)) {
      clearInterval(this.updateIntervals.get(feed.id));
      this.updateIntervals.delete(feed.id);
    }
    
    // Schedule the feed
    if (!feed.disabled) {
      this.scheduleFeed(feed);
    }
  }

  // Remove a feed from the scheduler
  removeFeed(feedId) {
    if (this.updateIntervals.has(feedId)) {
      clearInterval(this.updateIntervals.get(feedId));
      this.updateIntervals.delete(feedId);
    }
  }
}

// Export for use in extension
const feedScheduler = new FeedScheduler();