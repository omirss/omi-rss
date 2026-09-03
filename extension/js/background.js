// Background service worker for Omi RSS extension

// Import API service and sync manager
importScripts('./api.js');
importScripts('./sync-manager.js');
importScripts('./storage-service.js');
importScripts('./feed-parser.js');
importScripts('./feed-scheduler.js');
importScripts('./offline-db.js');
importScripts('./sync-service.js');

// WebSocket URL
const WS_URL = 'ws://localhost:8080/ws';

// Extension state
let wsConnection = null;
let syncEnabled = false;
let isAuthenticated = false;

// Initialize extension
chrome.runtime.onInstalled.addListener(async (details) => {
  console.log('Omi RSS Extension installed:', details.reason);
  
  // Set up context menus
  chrome.contextMenus.create({
    id: 'save-article',
    title: 'Save to Omi RSS',
    contexts: ['page', 'selection', 'link']
  });
  
  chrome.contextMenus.create({
    id: 'generate-feed',
    title: 'Generate RSS feed from this site',
    contexts: ['page']
  });
  
  chrome.contextMenus.create({
    id: 'save-selection',
    title: 'Save selection as note',
    contexts: ['selection']
  });
  
  chrome.contextMenus.create({
    id: 'add-feed',
    title: 'Subscribe to RSS feed',
    contexts: ['link']
  });
  
  // Initialize storage
  const { settings } = await chrome.storage.local.get('settings');
  if (!settings) {
    await chrome.storage.local.set({
      settings: {
        apiUrl: API_BASE,
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
  
  // Initialize API service and check auth
  await apiService.initializeAuth();
  isAuthenticated = !!apiService.token;
  if (auth?.token) {
    authToken = auth.token;
    connectWebSocket();
  }
});

// Handle context menu clicks
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  switch (info.menuItemId) {
    case 'save-article':
      await saveArticle(tab, info);
      break;
    case 'generate-feed':
      await generateFeed(tab);
      break;
    case 'save-selection':
      await saveSelection(info.selectionText, tab);
      break;
    case 'add-feed':
      await addFeedFromLink(info.linkUrl, tab);
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
      return true; // Keep channel open for async response
      
    case 'get-article-content':
      extractArticleContent(sender.tab)
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;
      
    case 'check-feed':
      checkForFeed(sender.tab)
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
      getFeeds()
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;
      
    case 'get-articles':
      getArticles(request.feedId, request.options)
        .then(sendResponse)
        .catch(err => sendResponse({ error: err.message }));
      return true;
      
    case 'mark-read':
      markArticleRead(request.articleId)
        .then(sendResponse)
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
  }
});

// Handle keyboard shortcuts
chrome.commands.onCommand.addListener(async (command) => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  
  switch (command) {
    case 'save-article':
      await saveArticle(tab);
      break;
    case 'toggle-reader':
      chrome.tabs.sendMessage(tab.id, { action: 'toggle-reader' });
      break;
  }
});

// Save article functionality
async function saveArticle(tab, info = {}) {
  try {
    // Show saving badge
    chrome.action.setBadgeText({ text: '...', tabId: tab.id });
    chrome.action.setBadgeBackgroundColor({ color: '#4CAF50' });
    
    // Extract article content
    const content = await extractArticleContent(tab);
    
    // Prepare article data
    const article = {
      url: info.linkUrl || tab.url,
      title: content.title || tab.title,
      content: content.content,
      excerpt: content.excerpt,
      author: content.author,
      publishedAt: content.publishedAt,
      imageUrl: content.imageUrl,
      savedFrom: 'browser_extension',
      tags: content.tags || []
    };
    
    // Save to backend
    const response = await fetch(`${API_BASE}/articles`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${authToken}`
      },
      body: JSON.stringify(article)
    });
    
    if (!response.ok) {
      throw new Error('Failed to save article');
    }
    
    const saved = await response.json();
    
    // Show success notification
    chrome.notifications.create({
      type: 'basic',
      iconUrl: '../icons/icon-128.png',
      title: 'Article Saved',
      message: saved.title,
      buttons: [
        { title: 'View' },
        { title: 'Add Tags' }
      ]
    });
    
    // Update badge
    chrome.action.setBadgeText({ text: '✓', tabId: tab.id });
    setTimeout(() => {
      chrome.action.setBadgeText({ text: '', tabId: tab.id });
    }, 2000);
    
    // Send to WebSocket if connected
    if (wsConnection?.readyState === WebSocket.OPEN) {
      wsConnection.send(JSON.stringify({
        type: 'article_saved',
        data: saved
      }));
    }
    
    return saved;
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
  // Try to find article content using various selectors
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
  
  // Extract metadata
  const getMetaContent = (name) => {
    const meta = document.querySelector(`meta[name="${name}"], meta[property="${name}"]`);
    return meta?.content || '';
  };
  
  // Clean content
  const clonedArticle = articleElement.cloneNode(true);
  
  // Remove unwanted elements
  const unwantedSelectors = [
    'script', 'style', 'nav', 'header', 'footer',
    '.advertisement', '.ads', '.social-share',
    '.comments', '.related-posts'
  ];
  
  unwantedSelectors.forEach(selector => {
    clonedArticle.querySelectorAll(selector).forEach(el => el.remove());
  });
  
  return {
    title: document.title || getMetaContent('og:title'),
    content: clonedArticle.innerHTML,
    excerpt: getMetaContent('description') || getMetaContent('og:description'),
    author: getMetaContent('author') || getMetaContent('article:author'),
    publishedAt: getMetaContent('article:published_time') || getMetaContent('datePublished'),
    imageUrl: getMetaContent('og:image') || document.querySelector('img')?.src,
    tags: getMetaContent('keywords')?.split(',').map(t => t.trim()).filter(Boolean) || []
  };
}

// Generate RSS feed from current site
async function generateFeed(tab) {
  try {
    chrome.action.setBadgeText({ text: '...', tabId: tab.id });
    
    // Get site info
    const url = new URL(tab.url);
    const siteUrl = url.origin;
    
    // Check if feed already exists
    const response = await fetch(`${API_BASE}/feeds/check?url=${encodeURIComponent(siteUrl)}`, {
      headers: {
        'Authorization': `Bearer ${authToken}`
      }
    });
    
    if (response.ok) {
      const { exists, feed } = await response.json();
      if (exists) {
        chrome.notifications.create({
          type: 'basic',
          iconUrl: '../icons/icon-128.png',
          title: 'Feed Already Exists',
          message: `${feed.title} is already in your feeds`
        });
        return;
      }
    }
    
    // Open feed generation in new tab
    const generatorUrl = chrome.runtime.getURL('generator.html') + `?url=${encodeURIComponent(tab.url)}`;
    chrome.tabs.create({ url: generatorUrl });
    
    chrome.action.setBadgeText({ text: '', tabId: tab.id });
  } catch (error) {
    console.error('Error generating feed:', error);
    chrome.action.setBadgeText({ text: '!', tabId: tab.id });
    chrome.action.setBadgeBackgroundColor({ color: '#F44336' });
  }
}

// Save selected text as note
async function saveSelection(text, tab) {
  try {
    const note = {
      content: text,
      sourceUrl: tab.url,
      sourceTitle: tab.title,
      type: 'selection',
      createdAt: new Date().toISOString()
    };
    
    const response = await fetch(`${API_BASE}/notes`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${authToken}`
      },
      body: JSON.stringify(note)
    });
    
    if (!response.ok) {
      throw new Error('Failed to save note');
    }
    
    chrome.notifications.create({
      type: 'basic',
      iconUrl: '../icons/icon-128.png',
      title: 'Selection Saved',
      message: text.substring(0, 100) + '...'
    });
  } catch (error) {
    console.error('Error saving selection:', error);
  }
}

// Check if current page has RSS/Atom feeds
async function checkForFeed(tab) {
  try {
    const [result] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: () => {
        const feeds = [];
        
        // Check for feed links in head
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
        
        // Check for common feed URLs
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

// WebSocket connection for real-time sync
function connectWebSocket() {
  if (!authToken || wsConnection?.readyState === WebSocket.OPEN) {
    return;
  }
  
  try {
    wsConnection = new WebSocket(`${WS_URL}?token=${authToken}`);
    
    wsConnection.onopen = () => {
      console.log('WebSocket connected');
      syncEnabled = true;
    };
    
    wsConnection.onmessage = (event) => {
      const message = JSON.parse(event.data);
      handleWebSocketMessage(message);
    };
    
    wsConnection.onerror = (error) => {
      console.error('WebSocket error:', error);
    };
    
    wsConnection.onclose = () => {
      console.log('WebSocket disconnected');
      syncEnabled = false;
      // Reconnect after 5 seconds
      setTimeout(connectWebSocket, 5000);
    };
  } catch (error) {
    console.error('Failed to connect WebSocket:', error);
  }
}

// Handle WebSocket messages
function handleWebSocketMessage(message) {
  switch (message.type) {
    case 'article_update':
      // Notify popup/sidepanel about article updates
      chrome.runtime.sendMessage({
        action: 'article-updated',
        data: message.data
      });
      break;
      
    case 'feed_update':
      // Update badge if new articles
      if (message.data.newCount > 0) {
        chrome.action.setBadgeText({ text: String(message.data.newCount) });
        chrome.action.setBadgeBackgroundColor({ color: '#2196F3' });
      }
      break;
      
    case 'sync_complete':
      // Refresh data in popup/sidepanel
      chrome.runtime.sendMessage({
        action: 'sync-complete',
        data: message.data
      });
      break;
  }
}

// Authentication handlers
async function handleLogin(credentials) {
  try {
    const response = await fetch(`${API_BASE}/auth/login`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(credentials)
    });
    
    if (!response.ok) {
      throw new Error('Login failed');
    }
    
    const { token, user } = await response.json();
    
    // Save auth data
    await chrome.storage.local.set({
      auth: { token, user }
    });
    
    authToken = token;
    connectWebSocket();
    
    return { success: true, user };
  } catch (error) {
    console.error('Login error:', error);
    throw error;
  }
}

async function handleLogout() {
  try {
    if (authToken) {
      await fetch(`${API_BASE}/auth/logout`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${authToken}`
        }
      });
    }
    
    // Clear auth data
    await chrome.storage.local.remove('auth');
    authToken = null;
    
    // Close WebSocket
    if (wsConnection) {
      wsConnection.close();
      wsConnection = null;
    }
    
    return { success: true };
  } catch (error) {
    console.error('Logout error:', error);
    throw error;
  }
}

// API handlers
async function getFeeds() {
  const response = await fetch(`${API_BASE}/feeds`, {
    headers: {
      'Authorization': `Bearer ${authToken}`
    }
  });
  
  if (!response.ok) {
    throw new Error('Failed to fetch feeds');
  }
  
  return response.json();
}

async function getArticles(feedId, options = {}) {
  const params = new URLSearchParams({
    limit: options.limit || 20,
    offset: options.offset || 0,
    unread: options.unread || false
  });
  
  const url = feedId 
    ? `${API_BASE}/feeds/${feedId}/articles?${params}`
    : `${API_BASE}/articles?${params}`;
  
  const response = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${authToken}`
    }
  });
  
  if (!response.ok) {
    throw new Error('Failed to fetch articles');
  }
  
  return response.json();
}

async function markArticleRead(articleId) {
  const response = await fetch(`${API_BASE}/articles/${articleId}/read`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${authToken}`
    }
  });
  
  if (!response.ok) {
    throw new Error('Failed to mark article as read');
  }
  
  return response.json();
}

async function updateSettings(settings) {
  await chrome.storage.local.set({ settings });
  
  // Update API URL if changed
  if (settings.apiUrl && settings.apiUrl !== API_BASE) {
    API_BASE = settings.apiUrl;
    // Reconnect WebSocket with new URL
    if (wsConnection) {
      wsConnection.close();
      connectWebSocket();
    }
  }
  
  return { success: true };
}

// Handle extension icon click - toggle popup or sidepanel
chrome.action.onClicked.addListener(async (tab) => {
  const { settings } = await chrome.storage.local.get('settings');
  
  if (settings?.preferSidePanel) {
    chrome.sidePanel.open({ windowId: tab.windowId });
  }
  // If not preferring sidepanel, the popup will open automatically
});

// Subscribe to a new feed
async function subscribeFeed(url) {
  try {
    // Check if feed already exists
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
      updateInterval: 3600000, // 1 hour default
      disabled: false,
      createdAt: new Date().toISOString()
    };
    
    const feedId = await storageService.addFeed(feedData);
    feedData.id = feedId;
    
    // Add articles
    const articles = await storageService.addArticles(result.feed.items, feedId);
    
    // Schedule feed updates
    feedScheduler.addOrUpdateFeed(feedData);
    
    // Update badge
    await feedScheduler.updateBadge();
    
    return { 
      success: true, 
      feed: feedData,
      articlesAdded: articles.length
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
        iconUrl: result.feed.favicon || '../icons/icon-128.png',
        title: 'Feed Added',
        message: `${result.feed.title} - ${result.articlesAdded} articles`,
        buttons: [
          { title: 'View Feed' }
        ]
      }, (notificationId) => {
        chrome.storage.local.set({ 
          [`notification_feed_${notificationId}`]: result.feed.id 
        });
      });
      
      chrome.action.setBadgeText({ text: '✓', tabId: tab.id });
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

// Delete feed
async function deleteFeed(feedId) {
  try {
    // Remove from scheduler
    feedScheduler.removeFeed(feedId);
    
    // Delete from storage
    await storageService.deleteFeed(feedId);
    
    // Update badge
    await feedScheduler.updateBadge();
    
    return { success: true };
  } catch (error) {
    console.error('Error deleting feed:', error);
    throw error;
  }
}

// Listen for notification clicks
chrome.notifications.onButtonClicked.addListener(async (notificationId, buttonIndex) => {
  if (buttonIndex === 0) { // "View Feed" button
    const result = await chrome.storage.local.get([`notification_feed_${notificationId}`]);
    const feedId = result[`notification_feed_${notificationId}`];
    
    if (feedId) {
      // Open feed in sidepanel or new tab
      const { settings } = await chrome.storage.local.get('settings');
      
      if (settings?.preferSidePanel) {
        chrome.sidePanel.open({ windowId: chrome.windows.WINDOW_ID_CURRENT });
        // Send message to sidepanel to show feed
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
      
      // Clean up
      chrome.storage.local.remove([`notification_feed_${notificationId}`]);
    }
  }
  
  chrome.notifications.clear(notificationId);
});