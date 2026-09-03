// Local-first sidepanel script for Omi RSS Extension
// This version works entirely with local storage without requiring a server

// Import storage service
let storageService;

// State management
const state = {
  currentView: 'all',
  feeds: [],
  articles: [],
  selectedFeed: null,
  selectedArticle: null,
  loading: false,
  searchQuery: ''
};

// DOM elements cache
const elements = {
  articleList: null,
  feedsList: null,
  readerContent: null,
  searchInput: null,
  loadingState: null,
  emptyState: null,
  articlesContainer: null,
  articleReader: null
};

// Initialize sidepanel
document.addEventListener('DOMContentLoaded', async () => {
  console.log('Omi RSS Local Sidepanel loaded');
  
  // Initialize storage service
  if (typeof StorageService !== 'undefined') {
    storageService = new StorageService();
    await storageService.init();
  } else {
    console.error('StorageService not loaded');
    return;
  }
  
  // Cache DOM elements
  cacheElements();
  
  // Initialize event listeners
  initializeEventListeners();
  
  // Load initial data
  await loadInitialData();
});

// Cache DOM elements for performance
function cacheElements() {
  elements.articleList = document.getElementById('article-list');
  elements.feedsList = document.getElementById('feeds-list');
  elements.readerContent = document.getElementById('reader-content');
  elements.searchInput = document.getElementById('search');
  elements.loadingState = document.getElementById('loading');
  elements.emptyState = document.getElementById('empty');
  elements.articlesContainer = document.getElementById('articles-container');
  elements.articleReader = document.getElementById('article-reader');
}

// Initialize event listeners
function initializeEventListeners() {
  // Header actions
  document.getElementById('refresh-btn')?.addEventListener('click', handleRefresh);
  document.getElementById('settings-btn')?.addEventListener('click', handleSettings);
  
  // Navigation
  document.querySelectorAll('.glass-nav-item').forEach(item => {
    item.addEventListener('click', handleNavigation);
  });
  
  // Search
  elements.searchInput?.addEventListener('input', debounce(handleSearch, 300));
  
  // Save current page
  document.getElementById('save-page-btn')?.addEventListener('click', handleSaveCurrentPage);
  
  // Detect feeds
  document.getElementById('detect-feeds-btn')?.addEventListener('click', handleDetectFeeds);
  
  // Add feed
  document.getElementById('add-feed-btn')?.addEventListener('click', handleAddFeed);
  
  // Reader controls
  document.getElementById('close-reader')?.addEventListener('click', closeReader);
  document.getElementById('toggle-read')?.addEventListener('click', toggleReadStatus);
  document.getElementById('save-article')?.addEventListener('click', saveArticle);
  document.getElementById('open-external')?.addEventListener('click', openInBrowser);
  
  // Listen for storage changes
  chrome.storage.onChanged.addListener((changes, namespace) => {
    if (namespace === 'local') {
      handleStorageChanges(changes);
    }
  });
}

// Load initial data
async function loadInitialData() {
  showLoading(true);
  
  try {
    await Promise.all([
      loadFeeds(),
      loadArticles()
    ]);
  } catch (error) {
    console.error('Failed to load initial data:', error);
    showError('Failed to load data. Please try refreshing.');
  } finally {
    showLoading(false);
  }
}

// Load feeds from local storage
async function loadFeeds() {
  try {
    state.feeds = await storageService.getAllFeeds();
    renderFeeds();
    updateCounts();
  } catch (error) {
    console.error('Failed to load feeds:', error);
    state.feeds = [];
  }
}

// Load articles from local storage
async function loadArticles(feedId = null) {
  try {
    let articles;
    
    if (feedId) {
      articles = await storageService.getArticlesByFeed(feedId);
    } else if (state.currentView === 'unread') {
      const allArticles = await storageService.getAllArticles();
      articles = allArticles.filter(a => !a.isRead);
    } else if (state.currentView === 'saved') {
      const allArticles = await storageService.getAllArticles();
      articles = allArticles.filter(a => a.isStarred);
    } else {
      articles = await storageService.getAllArticles();
    }
    
    // Sort by date
    articles.sort((a, b) => new Date(b.publishedAt) - new Date(a.publishedAt));
    
    state.articles = articles;
    renderArticles();
    updateCounts();
  } catch (error) {
    console.error('Failed to load articles:', error);
    state.articles = [];
    renderArticles();
  }
}

// Render feeds list
function renderFeeds() {
  if (!elements.feedsList) return;
  
  elements.feedsList.innerHTML = state.feeds.map(feed => {
    const unreadCount = feed.unreadCount || 0;
    return `
      <a href="#" class="glass-nav-item feed-item ${state.selectedFeed === feed.id ? 'active' : ''}" data-feed-id="${feed.id}">
        ${feed.favicon ? `
          <img src="${feed.favicon}" alt="" class="feed-icon" width="16" height="16">
        ` : `
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor">
            <circle cx="12" cy="12" r="10"/>
            <path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>
          </svg>
        `}
        <span class="feed-title">${escapeHtml(feed.title)}</span>
        ${unreadCount > 0 ? `<span class="count">${unreadCount}</span>` : ''}
      </a>
    `;
  }).join('');
  
  // Add click handlers
  elements.feedsList.querySelectorAll('.feed-item').forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const feedId = item.dataset.feedId;
      selectFeed(feedId);
    });
  });
}

// Render articles list
function renderArticles() {
  if (!elements.articlesContainer) return;
  
  if (state.articles.length === 0) {
    elements.loadingState.style.display = 'none';
    elements.emptyState.style.display = 'flex';
    elements.articlesContainer.innerHTML = '';
    return;
  }
  
  elements.loadingState.style.display = 'none';
  elements.emptyState.style.display = 'none';
  
  // Filter by search query if present
  let articles = state.articles;
  if (state.searchQuery) {
    articles = articles.filter(article => 
      article.title.toLowerCase().includes(state.searchQuery.toLowerCase()) ||
      (article.content && article.content.toLowerCase().includes(state.searchQuery.toLowerCase())) ||
      (article.author && article.author.toLowerCase().includes(state.searchQuery.toLowerCase()))
    );
  }
  
  elements.articlesContainer.innerHTML = articles.map(article => {
    const feed = state.feeds.find(f => f.id === article.feedId);
    return `
      <article class="glass-article-item ${article.isRead ? 'read' : 'unread'}" data-article-id="${article.id}">
        ${article.image ? `
          <div class="article-image">
            <img src="${article.image}" alt="" loading="lazy">
          </div>
        ` : ''}
        <div class="article-content">
          <h3 class="article-title">${escapeHtml(article.title)}</h3>
          <div class="article-meta">
            <span class="article-source">${escapeHtml(feed?.title || 'Unknown source')}</span>
            <span class="article-time">${formatTime(article.publishedAt)}</span>
            ${article.author ? `<span class="article-author">by ${escapeHtml(article.author)}</span>` : ''}
          </div>
          ${article.summary ? `<p class="article-excerpt">${escapeHtml(article.summary)}</p>` : ''}
          <div class="article-actions">
            <button class="glass-action-btn" data-action="toggle-read" title="${article.isRead ? 'Mark as unread' : 'Mark as read'}">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="${article.isRead ? 'currentColor' : 'none'}" stroke="currentColor">
                <circle cx="12" cy="12" r="10"/>
                ${article.isRead ? '<path d="m9 12 2 2 4-4"/>' : ''}
              </svg>
            </button>
            <button class="glass-action-btn" data-action="star" title="${article.isStarred ? 'Unstar' : 'Star'}">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="${article.isStarred ? 'currentColor' : 'none'}" stroke="currentColor">
                <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>
              </svg>
            </button>
            <button class="glass-action-btn" data-action="share" title="Share">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor">
                <path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/>
                <polyline points="16 6 12 2 8 6"/>
                <line x1="12" y1="2" x2="12" y2="15"/>
              </svg>
            </button>
          </div>
        </div>
      </article>
    `;
  }).join('');
  
  // Add click handlers
  elements.articlesContainer.querySelectorAll('.glass-article-item').forEach(item => {
    // Click on article to open it
    item.addEventListener('click', (e) => {
      if (!e.target.closest('.glass-action-btn')) {
        const articleId = item.dataset.articleId;
        const article = state.articles.find(a => a.id === articleId);
        if (article) {
          openArticle(article);
        }
      }
    });
    
    // Handle action buttons
    item.querySelectorAll('.glass-action-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const action = btn.dataset.action;
        const articleId = item.dataset.articleId;
        handleArticleAction(action, articleId);
      });
    });
  });
}

// Open article in reader
async function openArticle(article) {
  state.selectedArticle = article;
  
  // Show reader
  elements.articleList.style.display = 'none';
  elements.articleReader.style.display = 'block';
  
  // Check if we need to fetch full content
  let content = article.content || article.summary;
  if (!content && article.url) {
    // Try to extract full content
    try {
      const response = await chrome.runtime.sendMessage({
        action: 'extract-content',
        url: article.url
      });
      if (response && response.content) {
        content = response.content;
        // Update stored article with full content
        article.content = content;
        await storageService.updateArticle(article.id, { content });
      }
    } catch (error) {
      console.error('Failed to extract content:', error);
    }
  }
  
  // Render article content
  elements.readerContent.innerHTML = `
    <header class="reader-article-header">
      <h1>${escapeHtml(article.title)}</h1>
      <div class="reader-meta">
        <span>${escapeHtml(state.feeds.find(f => f.id === article.feedId)?.title || 'Unknown source')}</span>
        <span>•</span>
        <time>${formatTime(article.publishedAt)}</time>
        ${article.author ? `<span>• By ${escapeHtml(article.author)}</span>` : ''}
      </div>
    </header>
    ${article.image ? `
      <figure class="reader-image">
        <img src="${article.image}" alt="">
      </figure>
    ` : ''}
    <div class="reader-body">
      ${content || '<p>No content available</p>'}
    </div>
  `;
  
  // Mark as read if not already
  if (!article.isRead) {
    await markArticleRead(article.id);
  }
  
  // Update UI
  updateReaderActions();
}

// Close reader
function closeReader() {
  elements.articleReader.style.display = 'none';
  elements.articleList.style.display = 'block';
  state.selectedArticle = null;
}

// Handle navigation
function handleNavigation(e) {
  e.preventDefault();
  const navItem = e.currentTarget;
  const view = navItem.dataset.view;
  
  if (view) {
    // Update active state
    document.querySelectorAll('.glass-nav-item').forEach(item => {
      item.classList.remove('active');
    });
    navItem.classList.add('active');
    
    // Reset selected feed
    state.selectedFeed = null;
    
    // Update current view
    state.currentView = view;
    
    // Load appropriate content
    loadArticles();
  }
}

// Select feed
function selectFeed(feedId) {
  // Update active states
  document.querySelectorAll('.glass-nav-item').forEach(item => {
    item.classList.remove('active');
  });
  document.querySelector(`[data-feed-id="${feedId}"]`)?.classList.add('active');
  
  state.selectedFeed = feedId;
  state.currentView = 'feed';
  
  // Load articles for feed
  loadArticles(feedId);
}

// Handle refresh
async function handleRefresh() {
  const refreshBtn = document.getElementById('refresh-btn');
  refreshBtn.classList.add('spinning');
  
  try {
    // Update all feeds
    const feedParser = new FeedParser();
    let newArticlesCount = 0;
    
    for (const feed of state.feeds) {
      try {
        const parsedFeed = await feedParser.parseFeed(feed.url);
        
        // Save new articles
        for (const article of parsedFeed.articles) {
          const exists = await storageService.getArticle(article.id);
          if (!exists) {
            await storageService.saveArticle({
              ...article,
              feedId: feed.id,
              isRead: false,
              isStarred: false
            });
            newArticlesCount++;
          }
        }
        
        // Update feed
        await storageService.updateFeed(feed.id, {
          lastUpdated: new Date().toISOString(),
          errorCount: 0
        });
      } catch (error) {
        console.error(`Failed to update feed ${feed.title}:`, error);
        await storageService.updateFeed(feed.id, {
          errorCount: (feed.errorCount || 0) + 1,
          lastError: error.message
        });
      }
    }
    
    // Reload data
    await loadInitialData();
    
    if (newArticlesCount > 0) {
      showNotification(`Found ${newArticlesCount} new article${newArticlesCount > 1 ? 's' : ''}`);
    } else {
      showNotification('All feeds up to date');
    }
  } catch (error) {
    showError('Failed to refresh feeds');
  } finally {
    setTimeout(() => {
      refreshBtn.classList.remove('spinning');
    }, 500);
  }
}

// Handle settings
function handleSettings() {
  chrome.tabs.create({ url: chrome.runtime.getURL('settings.html') });
}

// Handle search
function handleSearch() {
  state.searchQuery = elements.searchInput.value.trim();
  renderArticles();
}

// Handle save current page
async function handleSaveCurrentPage() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    
    // Create article from current page
    const article = {
      id: `saved-${Date.now()}`,
      title: tab.title || 'Untitled',
      url: tab.url,
      summary: 'Saved from browser',
      publishedAt: new Date().toISOString(),
      isRead: false,
      isStarred: true,
      feedId: 'saved-pages'
    };
    
    await storageService.saveArticle(article);
    showNotification('Page saved successfully');
    
    // Refresh if viewing saved items
    if (state.currentView === 'saved') {
      await loadArticles();
    }
  } catch (error) {
    showError('Failed to save page');
  }
}

// Handle detect feeds
async function handleDetectFeeds() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    
    // Send message to content script to detect feeds
    const response = await chrome.tabs.sendMessage(tab.id, { action: 'detect-feeds' });
    
    if (response && response.feeds && response.feeds.length > 0) {
      showFeedDialog(response.feeds);
    } else {
      showNotification('No feeds found on this page');
    }
  } catch (error) {
    console.error('Failed to detect feeds:', error);
    showNotification('Could not detect feeds on this page');
  }
}

// Handle add feed
function handleAddFeed() {
  const dialog = document.createElement('div');
  dialog.className = 'glass-dialog-overlay';
  dialog.innerHTML = `
    <div class="glass-dialog">
      <h3>Add New Feed</h3>
      <input type="url" id="new-feed-url" placeholder="Enter feed URL..." class="glass-input">
      <div class="dialog-actions">
        <button class="glass-btn" onclick="this.closest('.glass-dialog-overlay').remove()">Cancel</button>
        <button class="glass-btn primary" id="add-feed-confirm">Add Feed</button>
      </div>
    </div>
  `;
  
  document.body.appendChild(dialog);
  
  const input = dialog.querySelector('#new-feed-url');
  const confirmBtn = dialog.querySelector('#add-feed-confirm');
  
  input.focus();
  
  confirmBtn.addEventListener('click', async () => {
    const url = input.value.trim();
    if (url) {
      await subscribeFeed(url);
      dialog.remove();
    }
  });
  
  input.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') {
      confirmBtn.click();
    }
  });
}

// Subscribe to a feed
async function subscribeFeed(url) {
  try {
    showLoading(true);
    
    const feedParser = new FeedParser();
    const parsedFeed = await feedParser.parseFeed(url);
    
    // Check if feed already exists
    const existingFeed = state.feeds.find(f => f.url === url);
    if (existingFeed) {
      showNotification('Feed already subscribed');
      return;
    }
    
    // Save feed
    const feed = {
      id: `feed-${Date.now()}`,
      title: parsedFeed.title,
      url: url,
      description: parsedFeed.description,
      favicon: parsedFeed.favicon,
      lastUpdated: new Date().toISOString(),
      unreadCount: parsedFeed.articles.length
    };
    
    await storageService.saveFeed(feed);
    
    // Save articles
    for (const article of parsedFeed.articles) {
      await storageService.saveArticle({
        ...article,
        feedId: feed.id,
        isRead: false,
        isStarred: false
      });
    }
    
    showNotification('Feed added successfully');
    await loadInitialData();
  } catch (error) {
    console.error('Failed to add feed:', error);
    showError('Failed to add feed. Please check the URL.');
  } finally {
    showLoading(false);
  }
}

// Handle article actions
async function handleArticleAction(action, articleId) {
  const article = state.articles.find(a => a.id === articleId);
  if (!article) return;
  
  switch (action) {
    case 'toggle-read':
      await toggleArticleRead(articleId);
      break;
    case 'star':
      await toggleArticleStar(articleId);
      break;
    case 'share':
      await shareArticle(article);
      break;
  }
}

// Mark article as read
async function markArticleRead(articleId) {
  try {
    await storageService.updateArticle(articleId, { isRead: true });
    
    // Update local state
    const article = state.articles.find(a => a.id === articleId);
    if (article) {
      article.isRead = true;
      updateCounts();
    }
  } catch (error) {
    console.error('Failed to mark article as read:', error);
  }
}

// Toggle article read status
async function toggleArticleRead(articleId) {
  const article = state.articles.find(a => a.id === articleId);
  if (!article) return;
  
  article.isRead = !article.isRead;
  await storageService.updateArticle(articleId, { isRead: article.isRead });
  
  renderArticles();
  updateCounts();
}

// Toggle article star status
async function toggleArticleStar(articleId) {
  const article = state.articles.find(a => a.id === articleId);
  if (!article) return;
  
  article.isStarred = !article.isStarred;
  await storageService.updateArticle(articleId, { isStarred: article.isStarred });
  
  renderArticles();
  showNotification(article.isStarred ? 'Article starred' : 'Article unstarred');
}

// Share article
async function shareArticle(article) {
  try {
    if (navigator.share) {
      await navigator.share({
        title: article.title,
        text: article.summary,
        url: article.url
      });
    } else {
      await navigator.clipboard.writeText(article.url);
      showNotification('Link copied to clipboard');
    }
  } catch (error) {
    if (error.name !== 'AbortError') {
      showError('Failed to share article');
    }
  }
}

// Toggle read status in reader
function toggleReadStatus() {
  if (state.selectedArticle) {
    toggleArticleRead(state.selectedArticle.id);
    updateReaderActions();
  }
}

// Save article from reader
function saveArticle() {
  if (state.selectedArticle) {
    toggleArticleStar(state.selectedArticle.id);
    updateReaderActions();
  }
}

// Open in browser
function openInBrowser() {
  if (state.selectedArticle) {
    chrome.tabs.create({ url: state.selectedArticle.url });
  }
}

// Update reader action buttons
function updateReaderActions() {
  if (!state.selectedArticle) return;
  
  const toggleReadBtn = document.getElementById('toggle-read');
  const saveBtn = document.getElementById('save-article');
  
  if (toggleReadBtn) {
    toggleReadBtn.classList.toggle('active', state.selectedArticle.isRead);
  }
  
  if (saveBtn) {
    saveBtn.classList.toggle('active', state.selectedArticle.isStarred);
  }
}

// Handle storage changes
function handleStorageChanges(changes) {
  // Reload data if feeds or articles changed
  if (changes.feeds || changes.articles) {
    loadInitialData();
  }
}

// Update counts
async function updateCounts() {
  const allArticles = await storageService.getAllArticles();
  const unreadCount = allArticles.filter(a => !a.isRead).length;
  const savedCount = allArticles.filter(a => a.isStarred).length;
  
  document.getElementById('all-count').textContent = allArticles.length;
  document.getElementById('unread-count').textContent = unreadCount;
  document.getElementById('saved-count').textContent = savedCount;
  
  // Update feed unread counts
  for (const feed of state.feeds) {
    const feedArticles = allArticles.filter(a => a.feedId === feed.id);
    const feedUnreadCount = feedArticles.filter(a => !a.isRead).length;
    feed.unreadCount = feedUnreadCount;
  }
}

// Show loading state
function showLoading(show) {
  state.loading = show;
  if (elements.loadingState) {
    elements.loadingState.style.display = show ? 'flex' : 'none';
  }
}

// Show notification
function showNotification(message, type = 'info') {
  const notification = document.createElement('div');
  notification.className = `glass-notification ${type}`;
  notification.textContent = message;
  
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

// Show error
function showError(message) {
  showNotification(message, 'error');
}

// Show feed dialog
function showFeedDialog(feeds) {
  const dialog = document.createElement('div');
  dialog.className = 'glass-dialog-overlay';
  dialog.innerHTML = `
    <div class="glass-dialog">
      <h3>Found ${feeds.length} feed${feeds.length > 1 ? 's' : ''}</h3>
      <div class="feed-list">
        ${feeds.map((feed, index) => `
          <label class="feed-option">
            <input type="checkbox" checked data-feed-index="${index}">
            <span>${escapeHtml(feed.title || feed.url)}</span>
          </label>
        `).join('')}
      </div>
      <div class="dialog-actions">
        <button class="glass-btn" onclick="this.closest('.glass-dialog-overlay').remove()">Cancel</button>
        <button class="glass-btn primary" id="subscribe-feeds">Subscribe</button>
      </div>
    </div>
  `;
  
  document.body.appendChild(dialog);
  
  document.getElementById('subscribe-feeds').addEventListener('click', async () => {
    const checkboxes = dialog.querySelectorAll('input[type="checkbox"]:checked');
    const selectedFeeds = Array.from(checkboxes).map(cb => feeds[parseInt(cb.dataset.feedIndex)]);
    
    for (const feed of selectedFeeds) {
      await subscribeFeed(feed.url);
    }
    
    dialog.remove();
  });
}

// Utility: Escape HTML
function escapeHtml(unsafe) {
  if (!unsafe) return '';
  return unsafe
    .toString()
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

// Utility: Format time
function formatTime(dateString) {
  if (!dateString) return 'Unknown';
  
  const date = new Date(dateString);
  const now = new Date();
  const diff = now - date;
  
  const minutes = Math.floor(diff / 60000);
  const hours = Math.floor(diff / 3600000);
  const days = Math.floor(diff / 86400000);
  
  if (minutes < 1) {
    return 'Just now';
  } else if (minutes < 60) {
    return `${minutes}m ago`;
  } else if (hours < 24) {
    return `${hours}h ago`;
  } else if (days < 7) {
    return `${days}d ago`;
  } else {
    return date.toLocaleDateString();
  }
}

// Utility: Debounce
function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}

// Add necessary styles
const style = document.createElement('style');
style.textContent = `
  .spinning {
    animation: spin 1s linear infinite;
  }
  
  @keyframes spin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }
  
  .glass-notification {
    position: fixed;
    bottom: 20px;
    right: 20px;
    padding: 16px 24px;
    background: rgba(255, 255, 255, 0.1);
    backdrop-filter: blur(10px);
    border: 1px solid rgba(255, 255, 255, 0.2);
    border-radius: 12px;
    color: white;
    transform: translateY(100px);
    transition: transform 0.3s ease;
    z-index: 1000;
  }
  
  .glass-notification.show {
    transform: translateY(0);
  }
  
  .glass-notification.error {
    background: rgba(244, 67, 54, 0.2);
    border-color: rgba(244, 67, 54, 0.3);
  }
  
  .glass-dialog-overlay {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0, 0, 0, 0.5);
    backdrop-filter: blur(5px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
  }
  
  .glass-dialog {
    background: rgba(255, 255, 255, 0.1);
    backdrop-filter: blur(20px);
    border: 1px solid rgba(255, 255, 255, 0.2);
    border-radius: 16px;
    padding: 24px;
    max-width: 500px;
    width: 90%;
    max-height: 80vh;
    overflow-y: auto;
  }
  
  .glass-dialog h3 {
    margin: 0 0 16px 0;
    color: white;
  }
  
  .glass-input {
    width: 100%;
    padding: 12px 16px;
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.2);
    border-radius: 8px;
    color: white;
    font-size: 14px;
    margin-bottom: 16px;
  }
  
  .glass-input::placeholder {
    color: rgba(255, 255, 255, 0.5);
  }
  
  .dialog-actions {
    display: flex;
    gap: 12px;
    justify-content: flex-end;
  }
  
  .glass-btn {
    padding: 8px 16px;
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.2);
    border-radius: 8px;
    color: white;
    cursor: pointer;
    font-size: 14px;
    transition: all 0.2s;
  }
  
  .glass-btn:hover {
    background: rgba(255, 255, 255, 0.2);
  }
  
  .glass-btn.primary {
    background: var(--primary-gradient);
    border: none;
  }
  
  .feed-list {
    margin: 16px 0;
  }
  
  .feed-option {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 0;
    color: white;
    cursor: pointer;
  }
  
  .feed-option input[type="checkbox"] {
    width: 16px;
    height: 16px;
  }
  
  .glass-article-item.read {
    opacity: 0.7;
  }
  
  .glass-action-btn {
    background: none;
    border: none;
    color: rgba(255, 255, 255, 0.7);
    cursor: pointer;
    padding: 4px;
    transition: color 0.2s;
  }
  
  .glass-action-btn:hover {
    color: white;
  }
  
  .glass-action-btn.active {
    color: var(--primary-color);
  }
`;
document.head.appendChild(style);