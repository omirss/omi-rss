// Popup script for Omi RSS Extension

// State
let currentView = 'main';
let currentTab = 'feeds';
let feeds = [];
let articles = [];
let savedItems = [];
let isAuthenticated = false;
let user = null;

// DOM elements
const app = document.getElementById('app');
const views = {
  loading: document.getElementById('loading'),
  login: document.getElementById('login-view'),
  main: document.getElementById('main-view'),
  settings: document.getElementById('settings-view')
};

// Initialize popup
document.addEventListener('DOMContentLoaded', async () => {
  // Always initialize event listeners
  initializeEventListeners();
  
  // Check if running in offline mode
  const isOffline = await checkOfflineMode();
  
  if (isOffline) {
    isAuthenticated = false;
    showView('main');
    loadOfflineData();
    updateOfflineUI();
  } else {
    await checkAuth();
    
    if (isAuthenticated) {
      showView('main');
      loadData();
    } else {
      showView('login');
    }
  }
});

// Check authentication status
async function checkAuth() {
  try {
    const { auth } = await chrome.storage.local.get('auth');
    if (auth?.token) {
      isAuthenticated = true;
      user = auth.user;
      return true;
    }
  } catch (error) {
    console.error('Auth check failed:', error);
  }
  return false;
}

// Show specific view
function showView(viewName) {
  Object.keys(views).forEach(key => {
    views[key].style.display = key === viewName ? 'flex' : 'none';
  });
  currentView = viewName;
}

// Initialize event listeners
function initializeEventListeners() {
  // Login form
  document.getElementById('login-form').addEventListener('submit', handleLogin);
  document.getElementById('use-offline').addEventListener('click', handleOfflineMode);
  document.getElementById('create-account').addEventListener('click', handleCreateAccount);
  
  // Header actions
  document.getElementById('save-page-btn').addEventListener('click', handleSavePage);
  document.getElementById('detect-feeds-btn').addEventListener('click', handleDetectFeeds);
  document.getElementById('refresh-btn').addEventListener('click', handleRefresh);
  document.getElementById('settings-btn').addEventListener('click', () => showView('settings'));
  
  // New action buttons
  document.getElementById('pop-out-btn').addEventListener('click', handlePopOut);
  document.getElementById('web-version-btn').addEventListener('click', handleWebVersion);
  document.getElementById('sidebar-btn').addEventListener('click', handleSidebar);
  
  // Tabs - Updated to use glass-tab class
  document.querySelectorAll('.glass-tab').forEach(tab => {
    tab.addEventListener('click', () => switchTab(tab.dataset.tab));
  });
  
  // Search
  document.getElementById('feed-search').addEventListener('input', filterFeeds);
  
  // Filters
  document.getElementById('feed-filter').addEventListener('change', filterArticles);
  document.getElementById('unread-filter').addEventListener('change', filterArticles);
  
  // Saved filters - Updated to use filter-pill class
  document.querySelectorAll('.filter-pill').forEach(chip => {
    chip.addEventListener('click', () => {
      // Update active state
      document.querySelectorAll('.filter-pill').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      // Re-render
      renderSavedItems();
    });
  });
  
  // Settings
  document.getElementById('back-btn').addEventListener('click', () => showView('main'));
  document.getElementById('logout-btn').addEventListener('click', handleLogout);
  
  // Settings toggles
  const settingsToggles = [
    'show-floating-button',
    'auto-detect-articles',
    'enable-reader-mode',
    'prefer-sidepanel',
    'auto-backup'
  ];
  
  settingsToggles.forEach(id => {
    const toggle = document.getElementById(id);
    if (toggle) {
      toggle.addEventListener('change', () => updateSetting(id, toggle.checked));
    }
  });
  
  // Sync buttons
  document.getElementById('webrtc-sync-btn')?.addEventListener('click', handleWebRTCSync);
  document.getElementById('export-sync-btn')?.addEventListener('click', handleExportSync);
  document.getElementById('import-sync-btn')?.addEventListener('click', handleImportSync);
  
  // Sync modal buttons
  document.getElementById('create-sync-btn')?.addEventListener('click', handleCreateSync);
  document.getElementById('join-sync-btn')?.addEventListener('click', handleJoinSync);
  document.getElementById('connect-btn')?.addEventListener('click', handleConnect);
  document.getElementById('copy-connection-btn')?.addEventListener('click', handleCopyConnection);
  
  // Load more
  document.getElementById('load-more-btn').addEventListener('click', loadMoreArticles);
  
  // Modal - Updated to handle glass modal
  const closeBtn = document.querySelector('.close-btn');
  if (closeBtn) {
    closeBtn.addEventListener('click', closeFeedModal);
  }
  
  // Add feed button
  document.getElementById('add-feed-btn').addEventListener('click', handleAddFeed);
}

// Handle login
async function handleLogin(e) {
  e.preventDefault();
  
  const email = document.getElementById('email').value;
  const password = document.getElementById('password').value;
  const serverUrl = document.getElementById('server-url').value;
  
  showLoading(true);
  
  try {
    // Update server URL if changed
    if (serverUrl) {
      await chrome.storage.local.set({
        settings: { apiUrl: serverUrl }
      });
    }
    
    const response = await chrome.runtime.sendMessage({
      action: 'login',
      credentials: { email, password }
    });
    
    if (response.error) {
      throw new Error(response.error);
    }
    
    isAuthenticated = true;
    user = response.user;
    showView('main');
    loadData();
  } catch (error) {
    showError('Login failed: ' + error.message);
  } finally {
    showLoading(false);
  }
}

// Handle offline mode
function handleOfflineMode(e) {
  e.preventDefault();
  
  // Set offline mode flag
  chrome.storage.local.set({ 
    offlineMode: true,
    offlineStartDate: new Date().toISOString()
  });
  
  // Show main view without authentication
  isAuthenticated = false;
  showView('main');
  
  // Load cached data if available
  loadOfflineData();
  
  // Show offline indicator
  showNotification('Running in offline mode. Some features may be limited.', 'info');
  
  // Update UI to show offline status
  updateOfflineUI();
}

// Handle create account
function handleCreateAccount(e) {
  e.preventDefault();
  chrome.tabs.create({ url: 'http://localhost:8080/register' });
}

// Handle save page
async function handleSavePage() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    
    // Check if online and authenticated
    if (isAuthenticated && !await checkOfflineMode()) {
      // Try to save via API
      const response = await chrome.runtime.sendMessage({
        action: 'save-article',
        data: { url: tab.url, title: tab.title }
      });
      
      if (response.error) {
        throw new Error(response.error);
      }
      
      // Also save locally for offline access
      await saveArticleLocally({
        id: response.id || Date.now().toString(),
        url: tab.url,
        title: tab.title,
        type: 'article',
        savedAt: new Date().toISOString()
      });
    } else {
      // Save locally only
      await saveArticleLocally({
        id: Date.now().toString(),
        url: tab.url,
        title: tab.title,
        type: 'article',
        savedAt: new Date().toISOString()
      });
    }
    
    // Refresh saved items
    if (currentTab === 'saved') {
      loadSavedItems();
    }
  } catch (error) {
    showError('Failed to save article: ' + error.message);
  }
}

// Handle detect feeds
async function handleDetectFeeds() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    
    // Check for feeds
    const response = await chrome.runtime.sendMessage({
      action: 'check-feed'
    });
    
    if (response.error) {
      throw new Error(response.error);
    }
    
    if (response.hasFeeds) {
      showFeedModal(response.feeds);
    } else {
      // Try common feed URLs
      showFeedModal(response.suggestions.map(url => ({
        url,
        title: 'Possible RSS feed',
        type: 'application/rss+xml'
      })));
    }
  } catch (error) {
    showError('Failed to detect feeds: ' + error.message);
  }
}

// Handle refresh
async function handleRefresh() {
  const refreshBtn = document.getElementById('refresh-btn');
  refreshBtn.classList.add('spinning');
  
  await loadData();
  
  setTimeout(() => {
    refreshBtn.classList.remove('spinning');
  }, 500);
}

// Handle logout
async function handleLogout() {
  try {
    await chrome.runtime.sendMessage({ action: 'logout' });
    isAuthenticated = false;
    user = null;
    showView('login');
  } catch (error) {
    showError('Logout failed: ' + error.message);
  }
}

// Handle pop out window
async function handlePopOut() {
  try {
    // Create a new window with the extension popup
    const extensionUrl = chrome.runtime.getURL('popup.html');
    await chrome.windows.create({
      url: extensionUrl,
      type: 'popup',
      width: 400,
      height: 700,
      focused: true
    });
    window.close();
  } catch (error) {
    console.error('Failed to create popup window:', error);
    showError('Failed to open in new window');
  }
}

// Handle web version
function handleWebVersion() {
  chrome.tabs.create({ url: 'http://localhost:3000' });
  window.close();
}

// Handle sidebar
async function handleSidebar() {
  try {
    // Check if sidePanel API is available (Chrome 114+)
    if (chrome.sidePanel) {
      await chrome.runtime.sendMessage({ action: 'open-sidepanel' });
      window.close();
    } else {
      // Fallback for Firefox and older Chrome versions
      // Open the sidepanel in a new tab
      chrome.tabs.create({ url: chrome.runtime.getURL('sidepanel.html') });
      window.close();
    }
  } catch (error) {
    console.error('Failed to open sidebar:', error);
    // Final fallback - open in new tab
    chrome.tabs.create({ url: chrome.runtime.getURL('sidepanel.html') });
    window.close();
  }
}

// Handle open app (legacy function - keeping for compatibility)
function handleOpenApp() {
  handleWebVersion();
}

// Handle open side panel (legacy function - keeping for compatibility)
async function handleOpenSidePanel() {
  await handleSidebar();
}

// Handle add feed
function handleAddFeed() {
  chrome.tabs.create({ url: 'http://localhost:3000/feeds/add' });
  window.close();
}

// Switch tab
function switchTab(tabName) {
  // Update tab buttons - use glass-tab class
  document.querySelectorAll('.glass-tab').forEach(tab => {
    tab.classList.toggle('active', tab.dataset.tab === tabName);
  });
  
  // Update tab content
  document.querySelectorAll('.tab-content').forEach(content => {
    content.style.display = content.id === `${tabName}-tab` ? 'flex' : 'none';
  });
  
  currentTab = tabName;
  
  // Load data for tab
  switch (tabName) {
    case 'feeds':
      loadFeeds();
      break;
    case 'articles':
      loadArticles();
      break;
    case 'saved':
      loadSavedItems();
      break;
  }
}

// Load data
async function loadData() {
  await Promise.all([
    loadFeeds(),
    loadArticles(),
    loadSavedItems(),
    loadSettings()
  ]);
}

// Load feeds
async function loadFeeds() {
  try {
    const response = await chrome.runtime.sendMessage({ action: 'get-feeds' });
    
    if (response.error) {
      throw new Error(response.error);
    }
    
    feeds = response.feeds || [];
    renderFeeds();
    
    // Save for offline use
    saveForOffline('feeds', feeds);
  } catch (error) {
    console.error('Failed to load feeds:', error);
    feeds = [];
    renderFeeds();
  }
}

// Render feeds
function renderFeeds() {
  const feedsList = document.getElementById('feeds-list');
  const emptyState = document.getElementById('feeds-empty');
  
  if (feeds.length === 0) {
    feedsList.style.display = 'none';
    emptyState.style.display = 'flex';
    return;
  }
  
  feedsList.style.display = 'block';
  emptyState.style.display = 'none';
  
  feedsList.innerHTML = feeds.map(feed => `
    <div class="feed-item" data-feed-id="${feed.id}">
      <div class="feed-icon">
        ${feed.favicon ? `<img src="${feed.favicon}" alt="">` : '📄'}
      </div>
      <div class="feed-info">
        <div class="feed-title">${escapeHtml(feed.title)}</div>
        <div class="feed-meta">${feed.unreadCount || 0} unread • Updated ${formatTime(feed.lastUpdated)}</div>
      </div>
      ${feed.unreadCount > 0 ? `<div class="feed-count">${feed.unreadCount}</div>` : ''}
    </div>
  `).join('');
  
  // Add click handlers
  feedsList.querySelectorAll('.feed-item').forEach(item => {
    item.addEventListener('click', () => {
      const feedId = item.dataset.feedId;
      switchTab('articles');
      document.getElementById('feed-filter').value = feedId;
      filterArticles();
    });
  });
  
  // Update feed filter dropdown
  const feedFilter = document.getElementById('feed-filter');
  feedFilter.innerHTML = '<option value="">All Feeds</option>' +
    feeds.map(feed => `<option value="${feed.id}">${escapeHtml(feed.title)}</option>`).join('');
}

// Filter feeds
function filterFeeds() {
  const searchTerm = document.getElementById('feed-search').value.toLowerCase();
  const feedItems = document.querySelectorAll('.feed-item');
  
  feedItems.forEach(item => {
    const title = item.querySelector('.feed-title').textContent.toLowerCase();
    item.style.display = title.includes(searchTerm) ? 'flex' : 'none';
  });
}

// Load articles
async function loadArticles(offset = 0) {
  try {
    const feedId = document.getElementById('feed-filter').value;
    const unreadOnly = document.getElementById('unread-filter').checked;
    
    const response = await chrome.runtime.sendMessage({
      action: 'get-articles',
      feedId,
      options: { offset, unread: unreadOnly }
    });
    
    if (response.error) {
      throw new Error(response.error);
    }
    
    if (offset === 0) {
      articles = response.articles || [];
    } else {
      articles.push(...(response.articles || []));
    }
    
    renderArticles();
    
    // Save for offline use (only save if it's the first page)
    if (offset === 0) {
      saveForOffline('articles', articles);
    }
    
    // Show/hide load more button
    const loadMoreBtn = document.getElementById('load-more-btn');
    loadMoreBtn.style.display = response.hasMore ? 'block' : 'none';
  } catch (error) {
    console.error('Failed to load articles:', error);
    articles = [];
    renderArticles();
  }
}

// Render articles
function renderArticles() {
  const articlesList = document.getElementById('articles-list');
  const emptyState = document.getElementById('articles-empty');
  
  if (articles.length === 0) {
    articlesList.style.display = 'none';
    emptyState.style.display = 'flex';
    return;
  }
  
  articlesList.style.display = 'block';
  emptyState.style.display = 'none';
  
  articlesList.innerHTML = articles.map(article => `
    <div class="article-item ${article.isRead ? '' : 'unread'}" data-article-id="${article.id}">
      <div class="article-header">
        <div class="article-title">${escapeHtml(article.title)}</div>
        <div class="article-time">${formatTime(article.publishedAt)}</div>
      </div>
      ${article.excerpt ? `<div class="article-excerpt">${escapeHtml(article.excerpt)}</div>` : ''}
      <div class="article-source">${escapeHtml(article.feed?.title || 'Unknown source')}</div>
    </div>
  `).join('');
  
  // Add click handlers
  articlesList.querySelectorAll('.article-item').forEach(item => {
    item.addEventListener('click', () => {
      const articleId = item.dataset.articleId;
      const article = articles.find(a => a.id === articleId);
      if (article) {
        openArticle(article);
      }
    });
  });
}

// Filter articles
function filterArticles() {
  loadArticles();
}

// Load more articles
function loadMoreArticles() {
  loadArticles(articles.length);
}

// Save article locally
async function saveArticleLocally(article) {
  try {
    // Get current saved articles
    const { savedArticles = [] } = await chrome.storage.local.get('savedArticles');
    
    // Check if already saved
    const existingIndex = savedArticles.findIndex(a => a.id === article.id || a.url === article.url);
    
    if (existingIndex === -1) {
      // Add to saved articles
      savedArticles.push({
        ...article,
        savedAt: new Date().toISOString()
      });
      
      // Save to storage
      await chrome.storage.local.set({ savedArticles });
      
      // Update local state
      savedItems = savedArticles;
      
      // If viewing saved items, re-render
      if (currentTab === 'saved') {
        renderSavedItems();
      }
      
      showNotification('Article saved locally');
      return true;
    } else {
      showNotification('Article already saved', 'info');
      return false;
    }
  } catch (error) {
    console.error('Failed to save article locally:', error);
    showError('Failed to save article');
    return false;
  }
}

// Remove saved article
async function removeSavedArticle(articleId) {
  try {
    // Get current saved articles
    const { savedArticles = [] } = await chrome.storage.local.get('savedArticles');
    
    // Remove article
    const filteredArticles = savedArticles.filter(a => a.id !== articleId);
    
    // Save to storage
    await chrome.storage.local.set({ savedArticles: filteredArticles });
    
    // Update local state
    savedItems = filteredArticles;
    
    // If viewing saved items, re-render
    if (currentTab === 'saved') {
      renderSavedItems();
    }
    
    showNotification('Article removed from saved');
    return true;
  } catch (error) {
    console.error('Failed to remove saved article:', error);
    showError('Failed to remove article');
    return false;
  }
}

// Open article
async function openArticle(article) {
  // Mark as read
  if (!article.isRead) {
    await chrome.runtime.sendMessage({
      action: 'mark-read',
      articleId: article.id
    });
  }
  
  // Open in new tab
  chrome.tabs.create({ url: article.url });
  
  // Close popup if preference is set
  const { settings } = await chrome.storage.local.get('settings');
  if (settings?.closeOnOpen) {
    window.close();
  }
}

// Load saved items
async function loadSavedItems() {
  try {
    // Try to load from API if online
    if (isAuthenticated && !await checkOfflineMode()) {
      const response = await chrome.runtime.sendMessage({
        action: 'get-saved-items'
      });
      
      if (response.error) {
        throw new Error(response.error);
      }
      
      savedItems = response.savedItems || [];
    } else {
      // Load from local storage
      const { savedArticles } = await chrome.storage.local.get('savedArticles');
      savedItems = savedArticles || [];
    }
    
    renderSavedItems();
    
    // Save for offline use
    if (savedItems.length > 0) {
      saveForOffline('saved', savedItems);
    }
  } catch (error) {
    console.error('Failed to load saved items:', error);
    // Fallback to local storage
    const { savedArticles } = await chrome.storage.local.get('savedArticles');
    savedItems = savedArticles || [];
    renderSavedItems();
  }
}

// Render saved items
function renderSavedItems() {
  const savedList = document.getElementById('saved-list');
  const emptyState = document.getElementById('saved-empty');
  
  if (savedItems.length === 0) {
    savedList.style.display = 'none';
    emptyState.style.display = 'flex';
    return;
  }
  
  savedList.style.display = 'block';
  emptyState.style.display = 'none';
  
  // Filter by current filter
  const filterChips = document.querySelectorAll('.filter-pill');
  let activeFilter = 'all';
  filterChips.forEach(chip => {
    if (chip.classList.contains('active')) {
      activeFilter = chip.dataset.filter;
    }
  });
  
  const filteredItems = savedItems.filter(item => {
    if (activeFilter === 'all') return true;
    if (activeFilter === 'articles') return item.type !== 'note';
    if (activeFilter === 'notes') return item.type === 'note';
    return true;
  });
  
  savedList.innerHTML = filteredItems.map(item => `
    <div class="saved-item ${item.type || 'article'}" data-item-id="${item.id || item.url}">
      <div class="saved-item-header">
        <h4>${escapeHtml(item.title || 'Untitled')}</h4>
        <button class="remove-saved-btn" data-id="${item.id || item.url}" title="Remove from saved">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor">
            <line x1="18" y1="6" x2="6" y2="18"/>
            <line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>
      ${item.excerpt || item.content ? `
        <p class="saved-item-excerpt">${escapeHtml((item.excerpt || item.content).substring(0, 150))}...</p>
      ` : ''}
      <div class="saved-item-meta">
        <span>${item.feed?.title || item.source || 'Unknown source'}</span>
        <span>•</span>
        <span>${formatTime(item.savedAt || item.publishedAt)}</span>
      </div>
    </div>
  `).join('');
  
  // Add click handlers
  savedList.querySelectorAll('.saved-item').forEach(item => {
    item.addEventListener('click', (e) => {
      if (!e.target.closest('.remove-saved-btn')) {
        const itemId = item.dataset.itemId;
        const savedItem = savedItems.find(i => (i.id || i.url) === itemId);
        if (savedItem && savedItem.url) {
          chrome.tabs.create({ url: savedItem.url });
        }
      }
    });
  });
  
  // Add remove handlers
  savedList.querySelectorAll('.remove-saved-btn').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const itemId = btn.dataset.id;
      await removeSavedArticle(itemId);
    });
  });
}

// Filter saved items
function filterSaved(filter) {
  document.querySelectorAll('.filter-pill').forEach(chip => {
    chip.classList.toggle('active', chip.dataset.filter === filter);
  });
  
  // Re-render saved items with new filter
  renderSavedItems();
}

// Load settings
async function loadSettings() {
  try {
    const { settings } = await chrome.storage.local.get('settings');
    
    if (settings) {
      // Update toggles
      document.getElementById('show-floating-button').checked = settings.showFloatingButton || false;
      document.getElementById('auto-detect-articles').checked = settings.autoDetectArticles || false;
      document.getElementById('enable-reader-mode').checked = settings.enableReaderMode !== false;
      document.getElementById('prefer-sidepanel').checked = settings.preferSidePanel || false;
      document.getElementById('enable-sync').checked = settings.enableSync || false;
      document.getElementById('settings-server-url').value = settings.apiUrl || 'http://localhost:8080';
    }
    
    // Update user info
    if (user) {
      document.getElementById('user-info').innerHTML = `
        <div>Signed in as: <strong>${escapeHtml(user.email)}</strong></div>
      `;
    }
  } catch (error) {
    console.error('Failed to load settings:', error);
  }
}

// Update setting
async function updateSetting(key, value) {
  try {
    const { settings = {} } = await chrome.storage.local.get('settings');
    
    // Convert kebab-case to camelCase
    const settingKey = key.replace(/-([a-z])/g, (g) => g[1].toUpperCase());
    settings[settingKey] = value;
    
    await chrome.runtime.sendMessage({
      action: 'update-settings',
      settings
    });
    
    showNotification('Settings updated');
  } catch (error) {
    showError('Failed to update settings: ' + error.message);
  }
}

// Show feed modal
function showFeedModal(detectedFeeds) {
  const modal = document.getElementById('feed-modal');
  const feedsContainer = document.getElementById('detected-feeds');
  
  feedsContainer.innerHTML = detectedFeeds.map((feed, index) => `
    <div class="detected-feed">
      <div class="detected-feed-title">${escapeHtml(feed.title)}</div>
      <div class="detected-feed-url">${escapeHtml(feed.url)}</div>
      <button class="btn btn-primary" data-feed-url="${escapeHtml(feed.url)}">Subscribe</button>
    </div>
  `).join('');
  
  // Add subscribe handlers
  feedsContainer.querySelectorAll('.btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const feedUrl = btn.dataset.feedUrl;
      await subscribeFeed(feedUrl);
      closeFeedModal();
    });
  });
  
  modal.style.display = 'flex';
}

// Close feed modal
function closeFeedModal() {
  document.getElementById('feed-modal').style.display = 'none';
}

// Subscribe to feed
async function subscribeFeed(feedUrl) {
  try {
    // TODO: Implement subscribe API
    showNotification('Subscribed to feed');
    await loadFeeds();
  } catch (error) {
    showError('Failed to subscribe: ' + error.message);
  }
}

// Utility functions
function showLoading(show) {
  views.loading.style.display = show ? 'flex' : 'none';
}

function showNotification(message) {
  // TODO: Implement notification UI
  console.log('Notification:', message);
}

function showError(message) {
  // TODO: Implement error UI
  console.error('Error:', message);
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

function formatTime(date) {
  if (!date) return 'Never';
  
  const d = new Date(date);
  const now = new Date();
  const diff = now - d;
  
  if (diff < 60000) return 'Just now';
  if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
  if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
  if (diff < 604800000) return `${Math.floor(diff / 86400000)}d ago`;
  
  return d.toLocaleDateString();
}

// Listen for messages from background
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  switch (request.action) {
    case 'article-updated':
      // Update article in list if visible
      const article = articles.find(a => a.id === request.data.id);
      if (article) {
        Object.assign(article, request.data);
        renderArticles();
      }
      break;
      
    case 'sync-complete':
      // Refresh data
      loadData();
      break;
  }
});

// Offline Mode Functions

// Load offline data from local storage
async function loadOfflineData() {
  try {
    const offlineData = await chrome.storage.local.get(['offlineFeeds', 'offlineArticles', 'offlineSaved']);
    
    if (offlineData.offlineFeeds) {
      feeds = offlineData.offlineFeeds;
      renderFeeds();
    }
    
    if (offlineData.offlineArticles) {
      articles = offlineData.offlineArticles;
      renderArticles();
    }
    
    if (offlineData.offlineSaved) {
      savedItems = offlineData.offlineSaved;
      renderSavedItems();
    }
    
    // If no offline data, show empty state
    if (!offlineData.offlineFeeds && !offlineData.offlineArticles) {
      showNotification('No offline data available. Connect to internet to sync.', 'warning');
    }
  } catch (error) {
    console.error('Failed to load offline data:', error);
    showError('Failed to load offline data');
  }
}

// Update UI for offline mode
function updateOfflineUI() {
  // Add offline indicator to header
  const headerTop = document.querySelector('.header-top');
  if (headerTop && !document.getElementById('offline-indicator')) {
    const indicator = document.createElement('div');
    indicator.id = 'offline-indicator';
    indicator.className = 'offline-indicator';
    indicator.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor">
        <path d="M18.36 5.64a9 9 0 1 1-12.73 0"/>
        <line x1="12" y1="2" x2="12" y2="12"/>
      </svg>
      <span>Offline Mode</span>
    `;
    headerTop.appendChild(indicator);
  }
  
  // Disable features that require connection
  const disableButtons = ['open-app-btn', 'detect-feeds-btn'];
  disableButtons.forEach(id => {
    const btn = document.getElementById(id);
    if (btn) {
      btn.disabled = true;
      btn.title = 'Not available in offline mode';
    }
  });
  
  // Update feed filter to only show cached feeds
  const feedFilter = document.getElementById('feed-filter');
  if (feedFilter) {
    feedFilter.innerHTML = '<option value="">Cached Feeds Only</option>' +
      feeds.map(feed => `<option value="${feed.id}">${escapeHtml(feed.title)}</option>`).join('');
  }
}

// Save data for offline use
async function saveForOffline(dataType, data) {
  try {
    const key = `offline${dataType.charAt(0).toUpperCase() + dataType.slice(1)}`;
    await chrome.storage.local.set({ [key]: data });
  } catch (error) {
    console.error(`Failed to save ${dataType} for offline:`, error);
  }
}

// Check if running in offline mode
async function checkOfflineMode() {
  const { offlineMode } = await chrome.storage.local.get('offlineMode');
  return offlineMode === true;
}

// Exit offline mode
async function exitOfflineMode() {
  await chrome.storage.local.remove(['offlineMode', 'offlineStartDate']);
  // Reload the popup to reset state
  window.location.reload();
}

// Add notification function if it doesn't exist
function showNotification(message, type = 'info') {
  // Create notification element
  const notification = document.createElement('div');
  notification.className = `notification notification-${type}`;
  notification.innerHTML = `
    <div class="notification-content">
      ${type === 'error' ? '❌' : type === 'warning' ? '⚠️' : 'ℹ️'} ${message}
    </div>
  `;
  
  document.body.appendChild(notification);
  
  // Animate in
  setTimeout(() => {
    notification.classList.add('show');
  }, 10);
  
  // Remove after delay
  setTimeout(() => {
    notification.classList.remove('show');
    setTimeout(() => notification.remove(), 300);
  }, 3000);
}

// Sync Handler Functions

// Handle WebRTC sync button click
async function handleWebRTCSync() {
  openSyncModal();
}

// Handle export sync
async function handleExportSync() {
  try {
    showLoading(true);
    const result = await chrome.runtime.sendMessage({ action: "export-sync" });
    
    if (result.error) {
      throw new Error(result.error);
    }
    
    showNotification(`Exported ${result.exportedItems.feeds} feeds and ${result.exportedItems.articles} articles`, "success");
  } catch (error) {
    showError("Export failed: " + error.message);
  } finally {
    showLoading(false);
  }
}

// Handle import sync
async function handleImportSync() {
  // Create file input
  const input = document.createElement("input");
  input.type = "file";
  input.accept = ".json";
  
  input.onchange = async (e) => {
    const file = e.target.files[0];
    if (\!file) return;
    
    try {
      showLoading(true);
      const content = await file.text();
      
      const result = await chrome.runtime.sendMessage({ 
        action: "import-sync",
        fileContent: content
      });
      
      if (result.error) {
        throw new Error(result.error);
      }
      
      showNotification(`Imported ${result.importedItems.feeds} feeds and ${result.importedItems.articles} articles`, "success");
      
      // Reload data
      await loadData();
    } catch (error) {
      showError("Import failed: " + error.message);
    } finally {
      showLoading(false);
    }
  };
  
  input.click();
}

// Sync Modal Functions
function openSyncModal() {
  document.getElementById("sync-modal").style.display = "flex";
  resetSyncModal();
}

function closeSyncModal() {
  document.getElementById("sync-modal").style.display = "none";
  resetSyncModal();
}

function resetSyncModal() {
  // Hide all sections
  document.getElementById("sync-choice").style.display = "block";
  document.getElementById("sync-qr").style.display = "none";
  document.getElementById("sync-join").style.display = "none";
  document.getElementById("sync-progress").style.display = "none";
}

// Handle create sync connection
async function handleCreateSync() {
  try {
    showSyncProgress("Creating connection...");
    
    const result = await chrome.runtime.sendMessage({ action: "start-webrtc-sync" });
    
    if (result.error) {
      throw new Error(result.error);
    }
    
    // Show QR code
    document.getElementById("sync-choice").style.display = "none";
    document.getElementById("sync-qr").style.display = "block";
    document.getElementById("sync-progress").style.display = "none";
    
    // Set QR code image
    document.getElementById("qr-code").src = result.qrCode;
    document.getElementById("connection-data").value = result.connectionData;
    
    // Start countdown timer
    startSyncTimer(result.expiresIn);
    
  } catch (error) {
    showError("Failed to create connection: " + error.message);
    resetSyncModal();
  }
}

// Handle join sync
function handleJoinSync() {
  document.getElementById("sync-choice").style.display = "none";
  document.getElementById("sync-join").style.display = "block";
}

// Handle connect
async function handleConnect() {
  const connectionData = document.getElementById("join-data").value.trim();
  
  if (\!connectionData) {
    showError("Please enter connection data");
    return;
  }
  
  try {
    showSyncProgress("Connecting...");
    
    const result = await chrome.runtime.sendMessage({ 
      action: "connect-webrtc",
      data: connectionData
    });
    
    if (result.error) {
      throw new Error(result.error);
    }
    
    showSyncProgress("Syncing data...");
    
    // Wait for sync to complete
    setTimeout(() => {
      showNotification("Sync completed successfully\!", "success");
      closeSyncModal();
      loadData(); // Reload data
    }, 2000);
    
  } catch (error) {
    showError("Connection failed: " + error.message);
    document.getElementById("sync-join").style.display = "block";
    document.getElementById("sync-progress").style.display = "none";
  }
}

// Handle copy connection data
function handleCopyConnection() {
  const connectionData = document.getElementById("connection-data");
  connectionData.select();
  document.execCommand("copy");
  showNotification("Connection data copied\!", "success");
}

// Show sync progress
function showSyncProgress(message) {
  document.getElementById("sync-choice").style.display = "none";
  document.getElementById("sync-qr").style.display = "none";
  document.getElementById("sync-join").style.display = "none";
  document.getElementById("sync-progress").style.display = "block";
  document.getElementById("sync-message").textContent = message;
}

// Start sync timer
function startSyncTimer(seconds) {
  const timerElement = document.getElementById("sync-timer");
  let remaining = seconds;
  
  const interval = setInterval(() => {
    remaining--;
    timerElement.textContent = remaining;
    
    if (remaining <= 0) {
      clearInterval(interval);
      showError("Connection expired");
      resetSyncModal();
    }
  }, 1000);
}

// Update sync status display
async function updateSyncStatus() {
  try {
    const status = await chrome.runtime.sendMessage({ action: "get-sync-status" });
    const statusElement = document.querySelector(".sync-status .status-value");
    
    if (statusElement) {
      if (status.lastSync) {
        const date = new Date(status.lastSync);
        const now = new Date();
        const diff = now - date;
        
        let timeAgo;
        if (diff < 60000) {
          timeAgo = "Just now";
        } else if (diff < 3600000) {
          timeAgo = `${Math.floor(diff / 60000)} minutes ago`;
        } else if (diff < 86400000) {
          timeAgo = `${Math.floor(diff / 3600000)} hours ago`;
        } else {
          timeAgo = `${Math.floor(diff / 86400000)} days ago`;
        }
        
        statusElement.textContent = `Last synced: ${timeAgo}`;
      } else {
        statusElement.textContent = "Not synced";
      }
    }
  } catch (error) {
    console.error("Failed to update sync status:", error);
  }
}

// Load sync status when showing settings
const originalShowView = showView;
showView = function(viewName) {
  originalShowView(viewName);
  if (viewName === "settings") {
    updateSyncStatus();
  }
}
