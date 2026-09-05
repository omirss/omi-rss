// Background service worker for Omi RSS extension

// Import shared config, API service, and local-first modules.
// On Firefox the same files are loaded via background.scripts in the manifest,
// where importScripts is unavailable.
if (typeof importScripts === 'function') {
  importScripts('./config.js');
  importScripts('./api.js');
  importScripts('./sync-manager.js');
  importScripts('./file-sync.js');
  importScripts('./storage-service.js');
  importScripts('./feed-parser.js');
  importScripts('./feed-scheduler.js');
}

const NOTIFICATION_ICON = chrome.runtime.getURL('icons/icon-128.png');

// Extension state
let isAuthenticated = false;

// Arm feed scheduling on every service worker wake. Timers die when the
// worker suspends, so start() re-creates the chrome.alarms tick each time.
feedScheduler.start();

async function refreshAuthState() {
  const token = await getAccessToken();
  isAuthenticated = !!token;
  return isAuthenticated;
}

// Initialize extension
chrome.runtime.onInstalled.addListener(async (details) => {
  console.log('Omi RSS Extension installed:', details.reason);

  // Set up context menus (clear first: 'install' also fires on update, and
  // recreating an existing id throws)
  await chrome.contextMenus.removeAll();

  chrome.contextMenus.create({
    id: 'save-article',
    title: 'Save to Omi RSS',
    contexts: ['page', 'selection', 'link']
  });

  chrome.contextMenus.create({
    id: 'add-feed',
    title: 'Subscribe to RSS feed',
    contexts: ['link']
  });

  chrome.contextMenus.create({
    id: 'generate-page-feed',
    title: 'Generate feed from this page',
    contexts: ['page']
  });

  // Initialize storage
  const { settings } = await chrome.storage.local.get('settings');
  if (!settings) {
    await chrome.storage.local.set({
      settings: {
        apiUrl: DEFAULT_SERVER_URL,
        theme: 'dark',
        autoSave: false,
        readerMode: true,
        syncEnabled: false
      }
    });
  }

  // Initialize storage service
  await storageService.ensureReady();

  // Start feed scheduler
  await feedScheduler.start();

  // Check auth
  await refreshAuthState();
});

// Handle context menu clicks
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  switch (info.menuItemId) {
    case 'save-article':
      await saveFromTab(tab, info);
      break;
    case 'add-feed':
      await addFeedFromLink(info.linkUrl, tab);
      break;
    case 'generate-page-feed':
      await startPagePicker(tab);
      break;
  }
});

// Handle messages from content scripts and popup
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  switch (request.action) {
    case 'save-article':
      handleSaveArticle(request.data, sender.tab)
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'get-article-content':
      extractArticleContent(sender.tab)
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'check-feed':
      getTargetTab(sender.tab)
        .then(tab => checkForFeed(tab))
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'login':
      handleLogin(request.credentials)
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'logout':
      handleLogout()
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'get-feeds':
      getServerFeeds()
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'get-articles':
      getServerArticles(request.feedId, request.options)
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'get-article':
      apiService.getArticle(request.articleId)
        .then(response => sendResponse({ article: normalizeServerArticle(response.article || response) }))
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'mark-read':
      markArticleReadOnServer(request.articleId)
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'get-saved-items':
      getSavedItems()
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'check-saved':
      isUrlSaved(request.url)
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'import-opml':
      apiService.importOPML(request.content)
        .then(result => sendResponse(result || { success: true }))
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'export-opml':
      apiService.exportOPML()
        .then(opml => sendResponse({ opml }))
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'open-sidepanel':
      chrome.sidePanel.open({ windowId: sender.tab.windowId });
      sendResponse({ success: true });
      break;

    case 'update-settings':
      updateSettings(request.settings)
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    // Local feed operations
    case 'subscribe-feed':
      subscribeFeed(request.url)
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'refresh-feed':
      feedScheduler.updateFeed(request.feedId)
        .then(() => sendResponse({ success: true }))
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'refresh-all-feeds':
      feedScheduler.updateAllFeeds()
        .then(results => sendResponse({ success: true, results }))
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'get-local-feeds':
      storageService.getAllFeeds()
        .then(feeds => sendResponse({ feeds }))
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'get-local-articles':
      storageService.getArticles(request.options)
        .then(articles => sendResponse({ articles }))
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'mark-article-read':
      storageService.markArticleRead(request.articleId, request.isRead)
        .then(article => sendResponse({ article }))
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'mark-article-saved':
      storageService.markArticleSaved(request.articleId, request.isSaved)
        .then(article => sendResponse({ article }))
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'delete-feed':
      deleteFeed(request.feedId)
        .then(() => sendResponse({ success: true }))
        .catch(err => sendResponse({ error: err.message }));
      return true;

    // Page-feed picker: on-demand injection of js/page-picker.js
    case 'start-page-picker':
      getTargetTab(sender.tab)
        .then(tab => startPagePicker(tab))
        .then(result => sendResponse(result))
        .catch(err => sendResponse({ error: err.message }));
      return true;

    case 'page-picker-context':
      refreshAuthState()
        .then(authed => sendResponse({ serverAvailable: authed }))
        .catch(() => sendResponse({ serverAvailable: false }));
      return true;

    case 'subscribe-page-feed':
      subscribePageFeed(request.data)
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;
  }
});

// Handle keyboard shortcuts
chrome.commands.onCommand.addListener(async (command) => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });

  switch (command) {
    case 'save-article':
      await saveFromTab(tab);
      break;
    case 'toggle-reader':
      chrome.tabs.sendMessage(tab.id, { action: 'toggle-reader' });
      break;
  }
});

// Save current page as a local item.
// The server has no direct article-upload endpoint, so saves are local-first.
async function handleSaveArticle(data = {}, tab = null) {
  const article = { ...data };

  if ((!article.content || !article.title) && tab) {
    try {
      Object.assign(article, await extractArticleContent(tab));
    } catch (err) {
      // Fall through with whatever data we have
    }
  }

  const item = {
    id: Date.now().toString(),
    url: article.url || (tab && tab.url) || '',
    title: article.title || (tab && tab.title) || 'Untitled',
    excerpt: article.excerpt || '',
    content: article.content || '',
    type: 'article',
    savedAt: new Date().toISOString()
  };

  const { savedArticles = [] } = await chrome.storage.local.get('savedArticles');

  if (item.url && savedArticles.some(a => a.url === item.url)) {
    return { success: true, alreadySaved: true, id: item.id, savedLocally: true, title: item.title };
  }

  savedArticles.unshift(item);
  await chrome.storage.local.set({ savedArticles });

  chrome.notifications.create({
    type: 'basic',
    iconUrl: NOTIFICATION_ICON,
    title: 'Article Saved',
    message: item.title
  });

  return { success: true, id: item.id, savedLocally: true, title: item.title };
}

async function isUrlSaved(url) {
  if (!url) return { saved: false };
  const { savedArticles = [] } = await chrome.storage.local.get('savedArticles');
  return { saved: savedArticles.some(a => a.url === url) };
}

async function getSavedItems() {
  const { savedArticles = [] } = await chrome.storage.local.get('savedArticles');
  return { savedItems: savedArticles };
}

// Context menu / command entry point with badge feedback
async function saveFromTab(tab, info = {}) {
  if (!tab) return;
  try {
    chrome.action.setBadgeText({ text: '...', tabId: tab.id });
    chrome.action.setBadgeBackgroundColor({ color: '#4CAF50' });

    const result = await handleSaveArticle({ url: info.linkUrl || tab.url }, tab);

    chrome.action.setBadgeText({ text: result.alreadySaved ? '-' : String.fromCharCode(10003), tabId: tab.id });
    setTimeout(() => {
      chrome.action.setBadgeText({ text: '', tabId: tab.id });
    }, 2000);

    return result;
  } catch (error) {
    console.error('Error saving article:', error);
    chrome.action.setBadgeText({ text: '!', tabId: tab.id });
    chrome.action.setBadgeBackgroundColor({ color: '#F44336' });
    setTimeout(() => {
      chrome.action.setBadgeText({ text: '', tabId: tab.id });
    }, 2000);
    throw error;
  }
}

// Extract article content using content script
async function extractArticleContent(tab) {
  try {
    // First try to get content from content script
    const response = await chrome.tabs.sendMessage(tab.id, {
      action: 'extract-content'
    });

    if (response?.content) {
      return response;
    }
  } catch (err) {
    // Content script might not be loaded
  }

  // Fallback: inject and run extraction script
  const [result] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: extractArticleFromPage
  });

  return result.result;
}

// Article extraction function (runs in page context)
function extractArticleFromPage() {
  const articleSelectors = [
    'article',
    '[role="article"]',
    '.article-content',
    '.post-content',
    '.entry-content',
    '#content',
    'main'
  ];

  let articleElement = null;
  for (const selector of articleSelectors) {
    const element = document.querySelector(selector);
    if (element && element.textContent.length > 500) {
      articleElement = element;
      break;
    }
  }

  if (!articleElement) {
    articleElement = document.body;
  }

  const getMetaContent = (name) => {
    const meta = document.querySelector(`meta[name="${name}"], meta[property="${name}"]`);
    return meta?.content || '';
  };

  const clonedArticle = articleElement.cloneNode(true);

  const unwantedSelectors = [
    'script', 'style', 'nav', 'header', 'footer',
    '.advertisement', '.ads', '.social-share',
    '.comments', '.related-posts'
  ];

  unwantedSelectors.forEach(selector => {
    clonedArticle.querySelectorAll(selector).forEach(el => el.remove());
  });

  return {
    url: window.location.href,
    title: getMetaContent('og:title') || document.title,
    content: clonedArticle.innerHTML,
    excerpt: getMetaContent('description') || getMetaContent('og:description'),
    author: getMetaContent('author') || getMetaContent('article:author'),
    publishedAt: getMetaContent('article:published_time') || getMetaContent('datePublished'),
    imageUrl: getMetaContent('og:image') || document.querySelector('img')?.src,
    tags: getMetaContent('keywords')?.split(',').map(t => t.trim()).filter(Boolean) || []
  };
}

// Resolve the tab a message action should run against.
// Messages from the popup have no sender.tab, so fall back to the active tab
// in the last focused window (not just any active tab - devtools and
// background windows can hold an "active" tab in their own window and must
// never receive injections meant for what the user is looking at).
// Extension pages (pop-out popup, sidepanel in a tab) report themselves as
// sender.tab but cannot be script-injected, so they also fall back — and the
// fallback must itself skip non-injectable tabs (the pop-out can be focused).
async function getTargetTab(tab) {
  if (tab && tab.url && !tab.url.startsWith('chrome-extension://')) return tab;
  const candidates = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  const injectable = candidates.filter(
    (candidate) => candidate.url && /^https?:\/\//.test(candidate.url),
  );
  return injectable[0] || candidates[0];
}

// Check if current page has RSS/Atom feeds
async function checkForFeed(tab) {
  if (!tab) {
    return { hasFeeds: false, feeds: [], suggestions: [] };
  }

  try {
    const [result] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: () => {
        const feeds = [];

        const feedLinks = document.querySelectorAll(
          'link[type="application/rss+xml"], link[type="application/atom+xml"]'
        );

        feedLinks.forEach(link => {
          feeds.push({
            url: link.href,
            title: link.title || 'RSS Feed',
            type: link.type
          });
        });

        const currentUrl = new URL(window.location.href);
        const commonPaths = ['/feed', '/rss', '/atom', '/feed.xml', '/rss.xml', '/atom.xml'];

        return {
          hasFeeds: feeds.length > 0,
          feeds,
          suggestions: commonPaths.map(path => currentUrl.origin + path)
        };
      }
    });

    return result.result;
  } catch (error) {
    console.error('Error checking for feeds:', error);
    return { hasFeeds: false, feeds: [], suggestions: [] };
  }
}

// Inject the page-feed picker into a tab. The picker file self-activates on
// load and guards against double-injection, so repeated calls just restart it.
// picker-selectors.js holds the pure selector helpers page-picker.js uses.
async function startPagePicker(tab) {
  tab = await getTargetTab(tab);
  if (!tab || !tab.id || !tab.url || !/^https?:\/\//.test(tab.url)) {
    return { error: 'The picker only works on http(s) pages' };
  }
  try {
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ['js/picker-selectors.js', 'js/page-picker.js']
    });
  } catch (error) {
    console.error('Picker injection failed:', error);
    const reason = error.message.includes('cannot access')
      ? 'this page cannot be scripted (browser-protected page?)'
      : error.message;
    return { error: `Could not attach the picker: ${reason}` };
  }
  return { success: true, tabId: tab.id };
}

// Subscribe to a page feed through the server extraction engine
// (POST /api/feeds/page). Page feeds cannot work without a server - the
// local-only sidepanel cannot monitor pages - so an unauthenticated caller
// gets an explicit 'noserver' result instead of a fake local feed.
async function subscribePageFeed(data = {}) {
  try {
    const token = await getAccessToken();
    if (!token) {
      return { error: 'noserver' };
    }

    const feed = await apiService.createPageFeed({
      pageUrl: data.pageUrl,
      pageSelector: data.pageSelector,
      title: data.title
    });

    console.log('Page feed created:', (feed && feed.feed && feed.feed.title) || data.pageUrl);
    return { success: true, feed: (feed && feed.feed) || feed };
  } catch (error) {
    console.error('Page feed subscribe failed:', error);
    return { error: error.message, status: error.status };
  }
}

// Authentication handlers
async function handleLogin(credentials) {
  try {
    const response = await apiService.login(credentials.email, credentials.password);

    isAuthenticated = true;

    return { success: true, user: response.user };
  } catch (error) {
    console.error('Login error:', error);
    throw error;
  }
}

async function handleLogout() {
  try {
    await apiService.logout();
    isAuthenticated = false;
    return { success: true };
  } catch (error) {
    console.error('Logout error:', error);
    throw error;
  }
}

// Server-backed handlers used by the popup
async function getServerFeeds() {
  const response = await apiService.getFeeds();
  const feeds = response.feeds || response || [];
  return { feeds };
}

function normalizeServerArticle(article) {
  return {
    ...article,
    url: article.link || article.url,
    excerpt: article.description || article.excerpt || '',
    feed: { title: article.feedTitle || (article.feed && article.feed.title) || '' }
  };
}

async function getServerArticles(feedId, options = {}) {
  const limit = options.limit || 20;
  const page = options.offset && limit ? Math.floor(options.offset / limit) + 1 : 1;

  const response = await apiService.getArticles({
    feedId: feedId || null,
    unread: !!options.unread,
    page,
    limit
  });

  const articles = (response.articles || []).map(normalizeServerArticle);
  const pagination = response.pagination || {};
  const hasMore = pagination.totalPages ? pagination.page < pagination.totalPages : false;

  return { articles, hasMore };
}

async function markArticleReadOnServer(articleId) {
  await apiService.markArticleRead(articleId, true);
  return { success: true };
}

async function updateSettings(settings) {
  const { settings: current = {} } = await chrome.storage.local.get('settings');
  await chrome.storage.local.set({ settings: { ...current, ...settings } });
  return { success: true };
}

// Handle extension icon click - toggle popup or sidepanel
chrome.action.onClicked.addListener(async (tab) => {
  const { settings } = await chrome.storage.local.get('settings');

  if (settings?.preferSidePanel) {
    chrome.sidePanel.open({ windowId: tab.windowId });
  }
});

// Subscribe to a new feed: local-first, then pushed to the server when signed in
async function subscribeFeed(url) {
  try {
    // Check if feed already exists locally
    const existingFeed = await storageService.getFeedByUrl(url);
    if (existingFeed) {
      return {
        success: false,
        error: 'Feed already subscribed',
        feed: existingFeed
      };
    }

    // Parse the feed
    const result = await feedParser.parseFeed(url);

    if (!result.success) {
      throw new Error(result.error);
    }

    // Get favicon
    const favicon = await feedParser.getFeedFavicon(result.feed);

    // Add feed to storage
    const feedData = {
      url: url,
      title: result.feed.title,
      description: result.feed.description,
      siteUrl: result.feed.siteUrl,
      favicon: favicon,
      updateInterval: 3600000,
      disabled: false,
      createdAt: new Date().toISOString()
    };

    const feedId = await storageService.addFeed(feedData);
    feedData.id = feedId;

    // Add articles
    const articles = await storageService.addArticles(result.feed.items, feedId);

    // Update badge
    await feedScheduler.updateBadge();

    // Push to server when authenticated (best-effort)
    let serverSynced = false;
    if (await getAccessToken()) {
      try {
        await apiService.createFeed(url);
        serverSynced = true;
      } catch (error) {
        console.error('Server subscribe failed (kept locally):', error);
      }
    }

    return {
      success: true,
      feed: feedData,
      articlesAdded: articles.length,
      serverSynced
    };
  } catch (error) {
    console.error('Error subscribing to feed:', error);
    throw error;
  }
}

// Add feed from link (context menu)
async function addFeedFromLink(url, tab) {
  try {
    chrome.action.setBadgeText({ text: '...', tabId: tab.id });
    chrome.action.setBadgeBackgroundColor({ color: '#2196F3' });

    const result = await subscribeFeed(url);

    if (result.success) {
      chrome.notifications.create({
        type: 'basic',
        iconUrl: result.feed.favicon || NOTIFICATION_ICON,
        title: 'Feed Added',
        message: `${result.feed.title} - ${result.articlesAdded} articles`
      }, (notificationId) => {
        chrome.storage.local.set({
          [`notification_feed_${notificationId}`]: result.feed.id
        });
      });

      chrome.action.setBadgeText({ text: String.fromCharCode(10003), tabId: tab.id });
    } else {
      chrome.action.setBadgeText({ text: '!', tabId: tab.id });
      chrome.action.setBadgeBackgroundColor({ color: '#F44336' });
    }

    setTimeout(() => {
      chrome.action.setBadgeText({ text: '', tabId: tab.id });
    }, 2000);

    return result;
  } catch (error) {
    chrome.action.setBadgeText({ text: '!', tabId: tab.id });
    chrome.action.setBadgeBackgroundColor({ color: '#F44336' });
    setTimeout(() => {
      chrome.action.setBadgeText({ text: '', tabId: tab.id });
    }, 2000);
    throw error;
  }
}

// Delete feed: local removal plus server unsubscribe (best-effort)
async function deleteFeed(feedId) {
  try {
    // Delete from storage
    await storageService.deleteFeed(feedId);

    // Update badge
    await feedScheduler.updateBadge();

    // Unsubscribe on the server when authenticated (best-effort)
    if (await getAccessToken()) {
      try {
        await apiService.deleteFeed(feedId);
      } catch (error) {
        console.error('Server unsubscribe failed (removed locally):', error);
      }
    }

    return { success: true };
  } catch (error) {
    console.error('Error deleting feed:', error);
    throw error;
  }
}

// Listen for notification clicks
chrome.notifications.onButtonClicked.addListener(async (notificationId, buttonIndex) => {
  if (buttonIndex === 0) {
    const result = await chrome.storage.local.get([`notification_feed_${notificationId}`]);
    const feedId = result[`notification_feed_${notificationId}`];

    if (feedId) {
      const { settings } = await chrome.storage.local.get('settings');

      if (settings?.preferSidePanel) {
        chrome.sidePanel.open({ windowId: chrome.windows.WINDOW_ID_CURRENT });
        setTimeout(() => {
          chrome.runtime.sendMessage({
            action: 'show-feed',
            feedId: feedId
          });
        }, 500);
      } else {
        chrome.tabs.create({
          url: chrome.runtime.getURL(`popup.html#feed/${feedId}`)
        });
      }

      chrome.storage.local.remove([`notification_feed_${notificationId}`]);
    }
  }

  chrome.notifications.clear(notificationId);
});
