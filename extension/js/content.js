// Content script for Omi RSS extension

// State
let readerModeActive = false;
let floatingButton = null;
let articleExtractor = null;

// Initialize content script
(function() {
  console.log('Omi RSS content script loaded');
  
  // Check if we should show floating save button
  chrome.storage.local.get('settings', ({ settings }) => {
    if (settings?.showFloatingButton) {
      createFloatingButton();
    }
  });
  
  // Listen for messages from background/popup
  chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    switch (request.action) {
      case 'extract-content':
        const content = extractArticleContent();
        sendResponse(content);
        break;
        
      case 'toggle-reader':
        toggleReaderMode();
        sendResponse({ success: true });
        break;
        
      case 'highlight-feeds':
        highlightFeedLinks();
        sendResponse({ success: true });
        break;
        
      case 'check-saved':
        checkIfArticleSaved()
          .then(sendResponse)
          .catch(err => sendResponse({ error: err.message }));
        return true;
    }
  });
  
  // Auto-detect articles
  detectArticle();
})();

// Create floating save button
function createFloatingButton() {
  if (floatingButton) return;
  
  floatingButton = document.createElement('div');
  floatingButton.id = 'omi-rss-floating-button';
  floatingButton.innerHTML = `
    <button class="omi-save-btn" title="Save to Omi RSS">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor">
        <path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/>
      </svg>
    </button>
  `;
  
  floatingButton.querySelector('button').addEventListener('click', async () => {
    try {
      floatingButton.classList.add('saving');
      const response = await chrome.runtime.sendMessage({
        action: 'save-article',
        data: extractArticleContent()
      });
      
      if (response.error) {
        throw new Error(response.error);
      }
      
      floatingButton.classList.remove('saving');
      floatingButton.classList.add('saved');
      
      setTimeout(() => {
        floatingButton.classList.remove('saved');
      }, 2000);
    } catch (error) {
      console.error('Error saving article:', error);
      floatingButton.classList.remove('saving');
      floatingButton.classList.add('error');
      
      setTimeout(() => {
        floatingButton.classList.remove('error');
      }, 2000);
    }
  });
  
  document.body.appendChild(floatingButton);
  
  // Position button based on scroll
  let ticking = false;
  function updateButtonPosition() {
    if (!ticking) {
      requestAnimationFrame(() => {
        const scrollPercent = window.scrollY / (document.body.scrollHeight - window.innerHeight);
        if (scrollPercent > 0.1 && scrollPercent < 0.9) {
          floatingButton.classList.add('visible');
        } else {
          floatingButton.classList.remove('visible');
        }
        ticking = false;
      });
      ticking = true;
    }
  }
  
  window.addEventListener('scroll', updateButtonPosition);
  updateButtonPosition();
}

// Extract article content
function extractArticleContent() {
  // Use Readability-like algorithm
  const article = findArticleElement();
  
  if (!article) {
    return {
      title: document.title,
      content: document.body.innerText,
      excerpt: '',
      error: 'Could not identify main article content'
    };
  }
  
  // Clone and clean article
  const cleaned = cleanArticleContent(article.cloneNode(true));
  
  // Extract metadata
  const metadata = extractMetadata();
  
  return {
    title: metadata.title || document.title,
    content: cleaned.innerHTML,
    text: cleaned.innerText,
    excerpt: metadata.excerpt || cleaned.innerText.substring(0, 200) + '...',
    author: metadata.author,
    publishedAt: metadata.publishedAt,
    imageUrl: metadata.imageUrl || findMainImage(article),
    tags: metadata.tags,
    readingTime: calculateReadingTime(cleaned.innerText)
  };
}

// Find main article element
function findArticleElement() {
  // Score elements based on various factors
  const candidates = [];
  const elements = document.querySelectorAll('article, [role="article"], main, .content, .article, .post, .entry');
  
  elements.forEach(element => {
    const score = scoreElement(element);
    if (score > 0) {
      candidates.push({ element, score });
    }
  });
  
  // Sort by score and return best candidate
  candidates.sort((a, b) => b.score - a.score);
  
  if (candidates.length > 0) {
    return candidates[0].element;
  }
  
  // Fallback: find element with most text content
  let bestElement = document.body;
  let maxTextLength = 0;
  
  document.querySelectorAll('div, section, main').forEach(element => {
    const textLength = element.innerText.length;
    const linkDensity = calculateLinkDensity(element);
    
    if (textLength > maxTextLength && textLength > 500 && linkDensity < 0.3) {
      maxTextLength = textLength;
      bestElement = element;
    }
  });
  
  return bestElement;
}

// Score element for article detection
function scoreElement(element) {
  let score = 0;
  
  // Tag name scores
  const tagScores = {
    article: 50,
    main: 30,
    section: 10,
    div: 5
  };
  
  score += tagScores[element.tagName.toLowerCase()] || 0;
  
  // Role attribute
  if (element.getAttribute('role') === 'article') {
    score += 30;
  }
  
  // Class and ID scores
  const classAndId = (element.className + ' ' + element.id).toLowerCase();
  const positiveWords = ['article', 'content', 'main', 'post', 'entry', 'text', 'body'];
  const negativeWords = ['sidebar', 'footer', 'header', 'nav', 'menu', 'comment', 'ad'];
  
  positiveWords.forEach(word => {
    if (classAndId.includes(word)) score += 10;
  });
  
  negativeWords.forEach(word => {
    if (classAndId.includes(word)) score -= 20;
  });
  
  // Text length
  const textLength = element.innerText.length;
  if (textLength > 1000) score += 20;
  if (textLength > 2000) score += 20;
  
  // Paragraph count
  const paragraphs = element.querySelectorAll('p').length;
  score += Math.min(paragraphs * 2, 30);
  
  // Link density penalty
  const linkDensity = calculateLinkDensity(element);
  if (linkDensity > 0.5) score -= 30;
  if (linkDensity > 0.3) score -= 20;
  
  return score;
}

// Calculate link density
function calculateLinkDensity(element) {
  const textLength = element.innerText.length;
  if (textLength === 0) return 0;
  
  let linkTextLength = 0;
  element.querySelectorAll('a').forEach(link => {
    linkTextLength += link.innerText.length;
  });
  
  return linkTextLength / textLength;
}

// Clean article content
function cleanArticleContent(element) {
  // Remove unwanted elements
  const unwantedSelectors = [
    'script',
    'style',
    'nav',
    'aside',
    'form',
    'button',
    '.share',
    '.social',
    '.advertisement',
    '.ad',
    '.promo',
    '.related',
    '.comments',
    '.sidebar',
    '.popup',
    '.modal'
  ];
  
  unwantedSelectors.forEach(selector => {
    element.querySelectorAll(selector).forEach(el => el.remove());
  });
  
  // Remove hidden elements
  element.querySelectorAll('*').forEach(el => {
    const style = window.getComputedStyle(el);
    if (style.display === 'none' || style.visibility === 'hidden') {
      el.remove();
    }
  });
  
  // Clean attributes
  element.querySelectorAll('*').forEach(el => {
    // Keep only essential attributes
    const keepAttributes = ['href', 'src', 'alt', 'title'];
    Array.from(el.attributes).forEach(attr => {
      if (!keepAttributes.includes(attr.name)) {
        el.removeAttribute(attr.name);
      }
    });
  });
  
  // Convert relative URLs to absolute
  element.querySelectorAll('a[href]').forEach(link => {
    link.href = new URL(link.getAttribute('href'), window.location.href).href;
  });
  
  element.querySelectorAll('img[src]').forEach(img => {
    img.src = new URL(img.getAttribute('src'), window.location.href).href;
  });
  
  return element;
}

// Extract metadata
function extractMetadata() {
  const getMetaContent = (names) => {
    for (const name of names) {
      const meta = document.querySelector(`meta[name="${name}"], meta[property="${name}"]`);
      if (meta?.content) return meta.content;
    }
    return null;
  };
  
  const getJsonLd = () => {
    try {
      const scripts = document.querySelectorAll('script[type="application/ld+json"]');
      for (const script of scripts) {
        const data = JSON.parse(script.textContent);
        if (data['@type'] === 'Article' || data['@type'] === 'NewsArticle') {
          return data;
        }
      }
    } catch (e) {}
    return null;
  };
  
  const jsonLd = getJsonLd();
  
  return {
    title: getMetaContent(['og:title', 'twitter:title']) || jsonLd?.headline,
    excerpt: getMetaContent(['description', 'og:description', 'twitter:description']) || jsonLd?.description,
    author: getMetaContent(['author', 'article:author']) || jsonLd?.author?.name,
    publishedAt: getMetaContent(['article:published_time', 'datePublished']) || jsonLd?.datePublished,
    imageUrl: getMetaContent(['og:image', 'twitter:image']) || jsonLd?.image,
    tags: getMetaContent(['keywords'])?.split(',').map(t => t.trim()).filter(Boolean) || []
  };
}

// Find main image
function findMainImage(article) {
  const images = article.querySelectorAll('img');
  let bestImage = null;
  let maxScore = 0;
  
  images.forEach(img => {
    const width = img.naturalWidth || parseInt(img.getAttribute('width')) || 0;
    const height = img.naturalHeight || parseInt(img.getAttribute('height')) || 0;
    const area = width * height;
    
    // Score based on size and position
    let score = area;
    
    // Bonus for being near the top
    const rect = img.getBoundingClientRect();
    if (rect.top < window.innerHeight) {
      score *= 1.5;
    }
    
    // Penalty for logos, icons
    const src = img.src.toLowerCase();
    if (src.includes('logo') || src.includes('icon') || width < 200 || height < 200) {
      score *= 0.1;
    }
    
    if (score > maxScore) {
      maxScore = score;
      bestImage = img;
    }
  });
  
  return bestImage?.src;
}

// Calculate reading time
function calculateReadingTime(text) {
  const wordsPerMinute = 200;
  const words = text.trim().split(/\s+/).length;
  const minutes = Math.ceil(words / wordsPerMinute);
  return minutes;
}

// Toggle reader mode
function toggleReaderMode() {
  if (readerModeActive) {
    disableReaderMode();
  } else {
    enableReaderMode();
  }
}

// Enable reader mode
function enableReaderMode() {
  const content = extractArticleContent();
  
  if (content.error) {
    alert('Could not extract article content');
    return;
  }
  
  // Create reader overlay
  const reader = document.createElement('div');
  reader.id = 'omi-reader-mode';
  reader.innerHTML = `
    <div class="reader-container">
      <div class="reader-header">
        <button class="reader-close" title="Close Reader Mode">×</button>
        <div class="reader-controls">
          <button class="reader-control" data-action="decrease-font" title="Decrease Font Size">A-</button>
          <button class="reader-control" data-action="increase-font" title="Increase Font Size">A+</button>
          <button class="reader-control" data-action="toggle-theme" title="Toggle Theme">🌓</button>
          <button class="reader-control" data-action="save" title="Save Article">💾</button>
        </div>
      </div>
      <article class="reader-content">
        <h1>${content.title}</h1>
        ${content.author ? `<div class="reader-meta">By ${content.author}</div>` : ''}
        <div class="reader-body">${content.content}</div>
      </article>
    </div>
  `;
  
  // Add event listeners
  reader.querySelector('.reader-close').addEventListener('click', disableReaderMode);
  
  reader.querySelectorAll('.reader-control').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const action = e.target.dataset.action;
      switch (action) {
        case 'increase-font':
          adjustFontSize(1);
          break;
        case 'decrease-font':
          adjustFontSize(-1);
          break;
        case 'toggle-theme':
          toggleReaderTheme();
          break;
        case 'save':
          saveFromReader();
          break;
      }
    });
  });
  
  document.body.appendChild(reader);
  document.body.style.overflow = 'hidden';
  readerModeActive = true;
  
  // Load saved preferences
  chrome.storage.local.get('readerPrefs', ({ readerPrefs }) => {
    if (readerPrefs) {
      if (readerPrefs.fontSize) {
        reader.style.setProperty('--reader-font-size', readerPrefs.fontSize + 'px');
      }
      if (readerPrefs.theme) {
        reader.classList.add(`theme-${readerPrefs.theme}`);
      }
    }
  });
}

// Disable reader mode
function disableReaderMode() {
  const reader = document.getElementById('omi-reader-mode');
  if (reader) {
    reader.remove();
    document.body.style.overflow = '';
    readerModeActive = false;
  }
}

// Adjust font size in reader
function adjustFontSize(delta) {
  const reader = document.getElementById('omi-reader-mode');
  const currentSize = parseInt(getComputedStyle(reader).getPropertyValue('--reader-font-size') || '18');
  const newSize = Math.max(12, Math.min(32, currentSize + delta * 2));
  
  reader.style.setProperty('--reader-font-size', newSize + 'px');
  
  // Save preference
  chrome.storage.local.get('readerPrefs', ({ readerPrefs = {} }) => {
    readerPrefs.fontSize = newSize;
    chrome.storage.local.set({ readerPrefs });
  });
}

// Toggle reader theme
function toggleReaderTheme() {
  const reader = document.getElementById('omi-reader-mode');
  const themes = ['light', 'dark', 'sepia'];
  
  let currentTheme = 'light';
  themes.forEach(theme => {
    if (reader.classList.contains(`theme-${theme}`)) {
      currentTheme = theme;
      reader.classList.remove(`theme-${theme}`);
    }
  });
  
  const nextTheme = themes[(themes.indexOf(currentTheme) + 1) % themes.length];
  reader.classList.add(`theme-${nextTheme}`);
  
  // Save preference
  chrome.storage.local.get('readerPrefs', ({ readerPrefs = {} }) => {
    readerPrefs.theme = nextTheme;
    chrome.storage.local.set({ readerPrefs });
  });
}

// Save from reader mode
async function saveFromReader() {
  const saveBtn = document.querySelector('[data-action="save"]');
  saveBtn.disabled = true;
  saveBtn.textContent = '⏳';
  
  try {
    const response = await chrome.runtime.sendMessage({
      action: 'save-article',
      data: extractArticleContent()
    });
    
    if (response.error) {
      throw new Error(response.error);
    }
    
    saveBtn.textContent = '✅';
    setTimeout(() => {
      saveBtn.textContent = '💾';
      saveBtn.disabled = false;
    }, 2000);
  } catch (error) {
    saveBtn.textContent = '❌';
    setTimeout(() => {
      saveBtn.textContent = '💾';
      saveBtn.disabled = false;
    }, 2000);
  }
}

// Highlight feed links on page
function highlightFeedLinks() {
  const feedLinks = document.querySelectorAll(
    'a[href*="/feed"], a[href*="/rss"], a[href*=".rss"], a[href*=".xml"], ' +
    'a[type="application/rss+xml"], a[type="application/atom+xml"]'
  );
  
  feedLinks.forEach(link => {
    link.style.cssText = `
      background-color: #ff6b00 !important;
      color: white !important;
      padding: 2px 6px !important;
      border-radius: 3px !important;
      text-decoration: none !important;
    `;
    
    link.title = 'RSS Feed - Click to subscribe in Omi RSS';
    
    link.addEventListener('click', (e) => {
      e.preventDefault();
      chrome.runtime.sendMessage({
        action: 'subscribe-feed',
        url: link.href
      });
    });
  });
  
  if (feedLinks.length > 0) {
    showNotification(`Found ${feedLinks.length} RSS feed(s) on this page`);
  }
}

// Show in-page notification
function showNotification(message) {
  const notification = document.createElement('div');
  notification.className = 'omi-notification';
  notification.textContent = message;
  
  document.body.appendChild(notification);
  
  setTimeout(() => {
    notification.classList.add('show');
  }, 100);
  
  setTimeout(() => {
    notification.classList.remove('show');
    setTimeout(() => notification.remove(), 300);
  }, 3000);
}

// Check if current article is already saved
async function checkIfArticleSaved() {
  try {
    const response = await chrome.runtime.sendMessage({
      action: 'check-saved',
      url: window.location.href
    });
    
    return response.saved;
  } catch (error) {
    return false;
  }
}

// Auto-detect if current page is an article
function detectArticle() {
  // Skip if not an article-like page
  const path = window.location.pathname;
  if (path === '/' || path.match(/\/(search|category|tag|page)\//)) {
    return;
  }
  
  // Check for article indicators
  const hasArticleTag = document.querySelector('article') !== null;
  const hasPublishDate = document.querySelector('[property="article:published_time"]') !== null;
  const hasLongText = document.body.innerText.length > 1000;
  
  if (hasArticleTag || hasPublishDate || hasLongText) {
    // Show floating button if enabled
    chrome.storage.local.get('settings', ({ settings }) => {
      if (settings?.autoDetectArticles) {
        createFloatingButton();
      }
    });
    
    // Check if already saved
    checkIfArticleSaved().then(saved => {
      if (saved && floatingButton) {
        floatingButton.classList.add('already-saved');
      }
    });
  }
}

// Listen for keyboard shortcuts
document.addEventListener('keydown', (e) => {
  // Ctrl/Cmd + Shift + S to save
  if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key === 'S') {
    e.preventDefault();
    chrome.runtime.sendMessage({
      action: 'save-article',
      data: extractArticleContent()
    });
  }
  
  // Ctrl/Cmd + Shift + R for reader mode
  if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key === 'R') {
    e.preventDefault();
    toggleReaderMode();
  }
});