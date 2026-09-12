// Feed Update Scheduler for Browser Extension
// MV3 service workers suspend when idle, so setInterval timers do not survive.
// Scheduling uses chrome.alarms: a single tick alarm wakes the worker on a
// fixed period and any feed past its next-due time is refreshed.
class FeedScheduler {
  constructor() {
    this.storageService = (typeof storageService !== 'undefined')
      ? storageService
      : new StorageService();
    this.feedParser = (typeof feedParser !== 'undefined')
      ? feedParser
      : new FeedParser();
    this.isRunning = false;
    this.defaultUpdateInterval = 3600000; // 1 hour
    this.minUpdateInterval = 300000; // 5 minutes
    this.maxUpdateInterval = 86400000; // 24 hours
    this.tickAlarmName = 'omi-feed-tick';
    this.tickPeriodMinutes = 1; // alarm API minimum granularity
    // Per-feed in-flight map: a manual refresh and an alarm tick for the
    // same feed must never overlap.
    this.inFlight = new Map();
  }

  // Start the scheduler. Safe to call on every service worker wake.
  async start() {
    if (this.isRunning) return;

    this.isRunning = true;

    // Arm the tick alarm first so scheduling survives worker suspension
    await chrome.alarms.create(this.tickAlarmName, {
      delayInMinutes: this.tickPeriodMinutes,
      periodInMinutes: this.tickPeriodMinutes
    });

    this.setupEventListeners();

    // Catch up on feeds that came due while the worker was suspended
    await this.checkStaleFeeds();
  }

  // Stop the scheduler
  async stop() {
    this.isRunning = false;
    await chrome.alarms.clear(this.tickAlarmName);
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

  // Update a single feed. Resolves { skipped, newArticles } with the REAL
  // new-article count (from addArticles' actual inserts — capped list
  // diffs undercount feeds already at the list limit); parse failures
  // THROW so callers can report them instead of recording success.
  async updateFeed(feedId) {
    if (this.inFlight.has(feedId)) {
      return { skipped: true, duplicate: true, newArticles: 0 };
    }
    this.inFlight.set(feedId, true);

    try {
      const feed = await this.storageService.getFeed(feedId);
      if (!feed || feed.disabled) {
        return { skipped: true, newArticles: 0 };
      }

      // Parse the feed
      const result = await this.feedParser.parseFeed(feed.url);

      if (!result.success) {
        await this.storageService.updateFeed(feedId, {
          errorCount: (feed.errorCount || 0) + 1,
          lastError: result.error
        });
        throw new Error(result.error);
      }

      // Update feed metadata
      await this.storageService.updateFeed(feedId, {
        title: result.feed.title,
        description: result.feed.description,
        lastUpdated: new Date().toISOString(),
        errorCount: 0,
        lastError: null
      });

      // Add new articles — addArticles maintains the unread count with
      // the inserts, so no stale pre-fetch overwrite happens here.
      const newArticles = await this.storageService.addArticles(result.feed.items, feedId);

      // Send notification if new articles
      if (newArticles.length > 0) {
        this.sendNewArticlesNotification(feed, newArticles.length);
      }

      // Update badge
      await this.updateBadge();

      console.log(`Updated feed "${feed.title}": ${newArticles.length} new articles`);
      return { skipped: false, newArticles: newArticles.length };
    } finally {
      this.inFlight.delete(feedId);
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

      // If feed is overdue for update, update it now. One failing feed
      // must not stop the rest of the sweep from running.
      if (timeSinceUpdate > updateInterval) {
        console.log(`Feed "${feed.title}" is stale, updating now...`);
        await this.updateFeed(feed.id).catch(error => {
          console.error(`Failed to update feed "${feed.title}":`, error);
        });
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

    // Update feeds in parallel (max 3 at a time); success/failed follows
    // the resolved/rejected distinction, not an unconditional counter.
    const batchSize = 3;
    for (let i = 0; i < feeds.length; i += batchSize) {
      const batch = feeds.slice(i, i + batchSize);

      await Promise.all(batch.map(async (feed) => {
        try {
          const result = await this.updateFeed(feed.id);
          results.newArticles += result.newArticles;
          results.success++;
        } catch (error) {
          console.error(`Failed to update feed "${feed.title}":`, error);
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
      iconUrl: feed.favicon || chrome.runtime.getURL('icons/icon-128.png'),
      title: title,
      message: message,
      buttons: [
        { title: 'Read now' }
      ]
    }, (notificationId) => {
      // Store feed ID for the background click handler
      chrome.storage.local.set({
        [`notification_feed_${notificationId}`]: feed.id
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
    // Tick: refresh any feeds past their due time
    chrome.alarms.onAlarm.addListener(async (alarm) => {
      if (alarm.name === this.tickAlarmName && this.isRunning) {
        await this.checkStaleFeeds();
      }
    });
  }
}

// Export for use in extension
const feedScheduler = new FeedScheduler();
