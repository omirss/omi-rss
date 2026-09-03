// Site-specific article extractors for complex websites

const siteExtractors = {
  // Medium
  'medium.com': {
    article: 'article',
    title: 'h1',
    author: '[data-testid="authorName"]',
    content: 'section',
    remove: ['.pw-post-paywall-overlay', '.meteredContent', '[data-testid="post-sidebar"]'],
    publishDate: 'time',
    processContent: (element) => {
      // Remove Medium-specific UI elements
      element.querySelectorAll('button, [role="toolbar"]').forEach(el => el.remove());
      return element;
    }
  },

  // Substack
  'substack.com': {
    article: 'article',
    title: 'h1.post-title',
    author: '.byline-wrapper a',
    content: '.available-content',
    remove: ['.subscription-widget-wrap', '.comments-section'],
    publishDate: '.post-date',
    imageUrl: (doc) => doc.querySelector('meta[property="og:image"]')?.content
  },

  // New York Times
  'nytimes.com': {
    article: '[data-testid="article-container"]',
    title: 'h1[data-testid="headline"]',
    author: '[itemprop="author"] [itemprop="name"]',
    content: 'section[name="articleBody"]',
    remove: ['.css-1fanzo5', '[data-testid="related-links-block"]'],
    publishDate: 'time',
    paywall: true,
    processContent: (element) => {
      // Handle lazy-loaded images
      element.querySelectorAll('img[data-src]').forEach(img => {
        img.src = img.dataset.src;
      });
      return element;
    }
  },

  // Washington Post
  'washingtonpost.com': {
    article: 'article',
    title: 'h1[data-qa="headline"]',
    author: '[data-qa="author-name"]',
    content: '[data-qa="article-body"]',
    remove: ['.pb-f-article-related-articles', '.pb-f-ads-arcads'],
    publishDate: '[data-qa="timestamp"]',
    paywall: true
  },

  // The Guardian
  'theguardian.com': {
    article: 'article',
    title: 'h1',
    author: '[itemprop="author"]',
    content: '[itemprop="articleBody"]',
    remove: ['.ad-slot', '.js-ad-slot', '.element-rich-link'],
    publishDate: 'time[itemprop="datePublished"]'
  },

  // BBC
  'bbc.com': {
    article: 'article',
    title: 'h1#main-heading',
    author: '[data-component="byline-block"]',
    content: '[data-component="text-block"]',
    remove: ['.ssrcss-1r97t5e-InjectedAdvertContainer'],
    publishDate: 'time',
    processContent: (element) => {
      // Combine all text blocks
      const blocks = element.parentElement.querySelectorAll('[data-component="text-block"]');
      const combined = document.createElement('div');
      blocks.forEach(block => combined.appendChild(block.cloneNode(true)));
      return combined;
    }
  },

  // TechCrunch
  'techcrunch.com': {
    article: 'article.article-container',
    title: 'h1.article__title',
    author: '.article__byline a',
    content: '.article-content',
    remove: ['.embed', '.ad-unit'],
    publishDate: 'time.article__published-date'
  },

  // The Verge
  'theverge.com': {
    article: 'article',
    title: 'h1',
    author: '[href*="/authors/"]',
    content: '.c-entry-content',
    remove: ['.c-related-list', '.c-article-footer'],
    publishDate: 'time'
  },

  // Ars Technica
  'arstechnica.com': {
    article: 'article',
    title: 'h1[itemprop="headline"]',
    author: '[itemprop="author"]',
    content: '[itemprop="articleBody"]',
    remove: ['.gallery', '.listing'],
    publishDate: 'time[itemprop="datePublished"]'
  },

  // Hacker News
  'news.ycombinator.com': {
    isLinkSite: true,
    getArticleUrl: () => {
      // Get the actual article URL from HN
      const storyLink = document.querySelector('.storylink, .titleline > a');
      return storyLink?.href;
    }
  },

  // Reddit
  'reddit.com': {
    article: '[data-test-id="post-content"]',
    title: 'h1',
    author: '[data-testid="post_author_link"]',
    content: '[data-test-id="post-content"]',
    publishDate: (doc) => {
      const timeElement = doc.querySelector('time');
      return timeElement?.getAttribute('datetime');
    },
    processContent: (element) => {
      // Handle Reddit's markdown content
      const textContent = element.querySelector('[data-click-id="text"]');
      if (textContent) {
        return textContent;
      }
      return element;
    }
  },

  // GitHub
  'github.com': {
    article: '.markdown-body',
    title: (doc) => {
      // For README files
      const h1 = doc.querySelector('.markdown-body h1');
      if (h1) return h1.textContent;
      // For other pages
      return doc.querySelector('[itemprop="name"]')?.textContent || doc.title;
    },
    content: '.markdown-body',
    remove: ['.anchor'],
    processContent: (element) => {
      // Convert relative links to absolute
      element.querySelectorAll('a[href^="/"]').forEach(link => {
        link.href = new URL(link.getAttribute('href'), window.location.origin).href;
      });
      return element;
    }
  },

  // Stack Overflow
  'stackoverflow.com': {
    article: '.question',
    title: 'h1[itemprop="name"]',
    author: '.user-details[itemprop="author"]',
    content: '.s-prose',
    processContent: (element) => {
      // Include the accepted answer if present
      const acceptedAnswer = document.querySelector('.accepted-answer .s-prose');
      if (acceptedAnswer) {
        const combined = document.createElement('div');
        combined.innerHTML = '<h2>Question</h2>';
        combined.appendChild(element.cloneNode(true));
        combined.innerHTML += '<h2>Accepted Answer</h2>';
        combined.appendChild(acceptedAnswer.cloneNode(true));
        return combined;
      }
      return element;
    }
  },

  // Wikipedia
  'wikipedia.org': {
    article: '#mw-content-text',
    title: 'h1.firstHeading',
    content: '#mw-content-text .mw-parser-output',
    remove: ['.navbox', '.ambox', '.sistersitebox', '.mw-empty-elt', '#toc', '.mw-editsection'],
    processContent: (element) => {
      // Remove edit links and clean up
      element.querySelectorAll('.reference').forEach(ref => {
        ref.textContent = '[' + ref.textContent + ']';
      });
      return element;
    }
  },

  // Dev.to
  'dev.to': {
    article: 'article',
    title: 'h1',
    author: '[itemprop="author"]',
    content: '[id="article-body"]',
    remove: ['.crayons-reaction', '.series-switcher'],
    publishDate: 'time'
  },

  // Forbes
  'forbes.com': {
    article: 'article',
    title: 'h1',
    author: '.by-author',
    content: '.article-body',
    remove: ['.vestpocket', '.top-ad-container'],
    paywall: true
  },

  // Bloomberg
  'bloomberg.com': {
    article: 'article',
    title: 'h1',
    author: '[rel="author"]',
    content: '.body-content',
    remove: ['.terminal-news-story', '.inline-newsletter'],
    paywall: true,
    processContent: (element) => {
      // Handle lazy-loaded content
      element.querySelectorAll('[data-native-src]').forEach(el => {
        const src = el.dataset.nativeSrc;
        if (el.tagName === 'IMG') {
          el.src = src;
        }
      });
      return element;
    }
  }
};

// Extract article using site-specific rules
function extractWithSiteRules(hostname) {
  // Find matching extractor
  let extractor = null;
  for (const [domain, rules] of Object.entries(siteExtractors)) {
    if (hostname.includes(domain)) {
      extractor = rules;
      break;
    }
  }

  if (!extractor) return null;

  // Handle link aggregator sites
  if (extractor.isLinkSite && extractor.getArticleUrl) {
    const articleUrl = extractor.getArticleUrl();
    if (articleUrl) {
      // Redirect to actual article
      window.location.href = articleUrl;
      return { redirect: true };
    }
  }

  const result = {
    title: '',
    author: '',
    content: '',
    publishDate: null,
    imageUrl: null
  };

  // Extract title
  if (typeof extractor.title === 'function') {
    result.title = extractor.title(document);
  } else if (extractor.title) {
    const titleEl = document.querySelector(extractor.title);
    result.title = titleEl?.textContent?.trim() || '';
  }

  // Extract author
  if (typeof extractor.author === 'function') {
    result.author = extractor.author(document);
  } else if (extractor.author) {
    const authorEl = document.querySelector(extractor.author);
    result.author = authorEl?.textContent?.trim() || '';
  }

  // Extract content
  let contentElement = null;
  if (extractor.content) {
    contentElement = document.querySelector(extractor.content);
  } else if (extractor.article) {
    contentElement = document.querySelector(extractor.article);
  }

  if (contentElement) {
    contentElement = contentElement.cloneNode(true);

    // Remove unwanted elements
    if (extractor.remove) {
      extractor.remove.forEach(selector => {
        contentElement.querySelectorAll(selector).forEach(el => el.remove());
      });
    }

    // Process content if custom processor exists
    if (extractor.processContent) {
      contentElement = extractor.processContent(contentElement);
    }

    result.content = contentElement.innerHTML;
    result.text = contentElement.textContent;
  }

  // Extract publish date
  if (typeof extractor.publishDate === 'function') {
    result.publishDate = extractor.publishDate(document);
  } else if (extractor.publishDate) {
    const dateEl = document.querySelector(extractor.publishDate);
    result.publishDate = dateEl?.getAttribute('datetime') || dateEl?.textContent?.trim();
  }

  // Extract image
  if (typeof extractor.imageUrl === 'function') {
    result.imageUrl = extractor.imageUrl(document);
  }

  // Add paywall flag
  if (extractor.paywall) {
    result.isPaywalled = true;
  }

  return result;
}

// Enhanced extraction for complex sites
function enhancedExtractContent() {
  const hostname = window.location.hostname;
  
  // Try site-specific extraction first
  const siteSpecific = extractWithSiteRules(hostname);
  if (siteSpecific?.redirect) {
    return siteSpecific;
  }

  // Get generic extraction
  const generic = extractArticleContent();

  // Merge results, preferring site-specific data
  if (siteSpecific) {
    return {
      ...generic,
      ...siteSpecific,
      title: siteSpecific.title || generic.title,
      author: siteSpecific.author || generic.author,
      content: siteSpecific.content || generic.content,
      text: siteSpecific.text || generic.text,
      publishedAt: siteSpecific.publishDate || generic.publishedAt,
      imageUrl: siteSpecific.imageUrl || generic.imageUrl,
      isPaywalled: siteSpecific.isPaywalled
    };
  }

  return generic;
}

// Replace the original extractArticleContent with enhanced version
window.extractArticleContent = enhancedExtractContent;