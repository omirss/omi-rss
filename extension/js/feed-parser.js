// Local RSS/Atom/JSON Feed Parser for Browser Extension
class FeedParser {
  constructor() {
    // CORS proxy options (fallback when direct fetch fails)
    this.corsProxies = [
      'https://cors-anywhere.herokuapp.com/',
      'https://api.allorigins.win/raw?url=',
      'https://cors-proxy.htmldriven.com/?url='
    ];
    this.currentProxyIndex = 0;
  }

  // Main parse method - auto-detects feed type
  async parseFeed(url, options = {}) {
    try {
      // Normalize URL
      url = this.normalizeUrl(url);
      
      // Fetch feed content
      const response = await this.fetchFeed(url, options);
      const contentType = response.headers.get('content-type') || '';
      const text = await response.text();
      
      // Try to detect and parse feed type
      let feedData;
      
      // Check if it's JSON
      if (contentType.includes('json') || text.trim().startsWith('{')) {
        feedData = await this.parseJSONFeed(text, url);
      } else {
        // Try parsing as XML (RSS/Atom)
        feedData = await this.parseXMLFeed(text, url);
      }
      
      // Validate and enhance feed data
      feedData = this.validateAndEnhanceFeed(feedData, url);
      
      return {
        success: true,
        feed: feedData,
        lastFetched: new Date().toISOString()
      };
    } catch (error) {
      console.error('Feed parsing error:', error);
      return {
        success: false,
        error: error.message,
        url: url
      };
    }
  }

  // Fetch feed with CORS handling
  async fetchFeed(url, options = {}) {
    const { useCorsProxy = true, timeout = 30000 } = options;
    
    // Create abort controller for timeout
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeout);
    
    try {
      // First try direct fetch
      const response = await fetch(url, {
        signal: controller.signal,
        headers: {
          'Accept': 'application/rss+xml, application/atom+xml, application/json, text/xml, */*'
        }
      });
      
      clearTimeout(timeoutId);
      
      if (response.ok) {
        return response;
      }
      
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    } catch (error) {
      clearTimeout(timeoutId);
      
      // If CORS error and proxy enabled, try with proxy
      if (useCorsProxy && (error.name === 'TypeError' || error.message.includes('CORS'))) {
        return this.fetchWithProxy(url, options);
      }
      
      throw error;
    }
  }

  // Fetch using CORS proxy
  async fetchWithProxy(url, options = {}) {
    const { timeout = 30000 } = options;
    
    for (let i = 0; i < this.corsProxies.length; i++) {
      const proxyUrl = this.corsProxies[this.currentProxyIndex] + encodeURIComponent(url);
      this.currentProxyIndex = (this.currentProxyIndex + 1) % this.corsProxies.length;
      
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), timeout);
        
        const response = await fetch(proxyUrl, {
          signal: controller.signal,
          headers: {
            'Accept': 'application/rss+xml, application/atom+xml, application/json, text/xml, */*'
          }
        });
        
        clearTimeout(timeoutId);
        
        if (response.ok) {
          return response;
        }
      } catch (error) {
        console.warn(`Proxy ${i + 1} failed:`, error.message);
      }
    }
    
    throw new Error('All CORS proxies failed. Please check the feed URL or try again later.');
  }

  // Parse XML feeds (RSS/Atom)
  async parseXMLFeed(xmlText, feedUrl) {
    const parser = new DOMParser();
    const doc = parser.parseFromString(xmlText, 'text/xml');
    
    // Check for parse errors
    const parseError = doc.querySelector('parsererror');
    if (parseError) {
      throw new Error('Invalid XML: ' + parseError.textContent);
    }
    
    // Detect feed type
    const rssElement = doc.querySelector('rss');
    const feedElement = doc.querySelector('feed');
    
    if (rssElement) {
      return this.parseRSSFeed(doc, feedUrl);
    } else if (feedElement) {
      return this.parseAtomFeed(doc, feedUrl);
    } else {
      throw new Error('Unknown XML feed format');
    }
  }

  // Parse RSS 2.0 feed
  parseRSSFeed(doc, feedUrl) {
    const channel = doc.querySelector('channel');
    if (!channel) {
      throw new Error('Invalid RSS feed: missing channel element');
    }
    
    // Extract feed metadata
    const feed = {
      type: 'rss',
      title: this.getTextContent(channel, 'title') || 'Untitled Feed',
      description: this.getTextContent(channel, 'description') || '',
      url: feedUrl,
      siteUrl: this.getTextContent(channel, 'link') || feedUrl,
      language: this.getTextContent(channel, 'language') || 'en',
      lastBuildDate: this.getTextContent(channel, 'lastBuildDate') || null,
      items: []
    };
    
    // Extract feed image
    const image = channel.querySelector('image');
    if (image) {
      feed.image = {
        url: this.getTextContent(image, 'url'),
        title: this.getTextContent(image, 'title'),
        link: this.getTextContent(image, 'link')
      };
    }
    
    // Parse items
    const items = channel.querySelectorAll('item');
    feed.items = Array.from(items).map(item => this.parseRSSItem(item));
    
    return feed;
  }

  // Parse RSS item
  parseRSSItem(item) {
    const article = {
      guid: this.getTextContent(item, 'guid') || this.getTextContent(item, 'link') || '',
      title: this.getTextContent(item, 'title') || 'Untitled',
      link: this.getTextContent(item, 'link') || '',
      description: this.getTextContent(item, 'description') || '',
      pubDate: this.getTextContent(item, 'pubDate') || null,
      author: this.getTextContent(item, 'author') || this.getTextContent(item, 'dc:creator') || '',
      categories: Array.from(item.querySelectorAll('category')).map(cat => cat.textContent?.trim() || ''),
      comments: this.getTextContent(item, 'comments') || null
    };
    
    // Extract content:encoded if available
    const contentEncoded = item.querySelector('content\\:encoded, encoded');
    if (contentEncoded) {
      article.content = contentEncoded.textContent || '';
    }
    
    // Extract media content
    const enclosure = item.querySelector('enclosure');
    if (enclosure) {
      article.enclosure = {
        url: enclosure.getAttribute('url'),
        type: enclosure.getAttribute('type'),
        length: enclosure.getAttribute('length')
      };
    }
    
    // Extract media:thumbnail
    const thumbnail = item.querySelector('media\\:thumbnail, thumbnail');
    if (thumbnail) {
      article.thumbnail = thumbnail.getAttribute('url');
    }
    
    return article;
  }

  // Parse Atom 1.0 feed
  parseAtomFeed(doc, feedUrl) {
    const feedElement = doc.querySelector('feed');
    
    // Extract feed metadata
    const feed = {
      type: 'atom',
      title: this.getTextContent(feedElement, 'title') || 'Untitled Feed',
      description: this.getTextContent(feedElement, 'subtitle') || '',
      url: feedUrl,
      siteUrl: this.getAtomLink(feedElement, 'alternate') || feedUrl,
      id: this.getTextContent(feedElement, 'id') || feedUrl,
      updated: this.getTextContent(feedElement, 'updated') || null,
      items: []
    };
    
    // Extract feed author
    const author = feedElement.querySelector('author');
    if (author) {
      feed.author = {
        name: this.getTextContent(author, 'name'),
        email: this.getTextContent(author, 'email'),
        uri: this.getTextContent(author, 'uri')
      };
    }
    
    // Parse entries
    const entries = feedElement.querySelectorAll('entry');
    feed.items = Array.from(entries).map(entry => this.parseAtomEntry(entry));
    
    return feed;
  }

  // Parse Atom entry
  parseAtomEntry(entry) {
    const article = {
      guid: this.getTextContent(entry, 'id') || '',
      title: this.getTextContent(entry, 'title') || 'Untitled',
      link: this.getAtomLink(entry, 'alternate') || '',
      summary: this.getTextContent(entry, 'summary') || '',
      content: '',
      published: this.getTextContent(entry, 'published') || this.getTextContent(entry, 'updated') || null,
      updated: this.getTextContent(entry, 'updated') || null,
      categories: Array.from(entry.querySelectorAll('category')).map(cat => 
        cat.getAttribute('term') || cat.textContent?.trim() || ''
      )
    };
    
    // Extract content
    const content = entry.querySelector('content');
    if (content) {
      article.content = content.textContent || '';
    }
    
    // Extract author
    const author = entry.querySelector('author');
    if (author) {
      article.author = this.getTextContent(author, 'name') || '';
    }
    
    return article;
  }

  // Parse JSON Feed
  async parseJSONFeed(jsonText, feedUrl) {
    let data;
    try {
      data = JSON.parse(jsonText);
    } catch (error) {
      throw new Error('Invalid JSON: ' + error.message);
    }
    
    // Validate JSON Feed
    if (!data.version || !data.version.startsWith('https://jsonfeed.org')) {
      throw new Error('Not a valid JSON Feed');
    }
    
    // Extract feed metadata
    const feed = {
      type: 'json',
      title: data.title || 'Untitled Feed',
      description: data.description || '',
      url: feedUrl,
      siteUrl: data.home_page_url || feedUrl,
      icon: data.icon || data.favicon || null,
      items: []
    };
    
    // Parse items
    if (Array.isArray(data.items)) {
      feed.items = data.items.map(item => this.parseJSONItem(item));
    }
    
    return feed;
  }

  // Parse JSON Feed item
  parseJSONItem(item) {
    return {
      guid: item.id || item.url || '',
      title: item.title || 'Untitled',
      link: item.url || item.external_url || '',
      summary: item.summary || '',
      content: item.content_html || item.content_text || '',
      published: item.date_published || null,
      modified: item.date_modified || null,
      author: item.author?.name || item.authors?.[0]?.name || '',
      image: item.image || item.banner_image || null,
      tags: item.tags || []
    };
  }

  // Helper: Get text content of element
  getTextContent(parent, selector) {
    const element = parent.querySelector(selector);
    return element?.textContent?.trim() || null;
  }

  // Helper: Get Atom link
  getAtomLink(parent, rel) {
    const links = parent.querySelectorAll('link');
    for (const link of links) {
      if (link.getAttribute('rel') === rel) {
        return link.getAttribute('href');
      }
    }
    return null;
  }

  // Normalize and validate feed URL
  normalizeUrl(url) {
    // Add protocol if missing
    if (!url.match(/^https?:\/\//i)) {
      url = 'https://' + url;
    }
    
    try {
      const urlObj = new URL(url);
      return urlObj.toString();
    } catch (error) {
      throw new Error('Invalid URL: ' + url);
    }
  }

  // Validate and enhance feed data
  validateAndEnhanceFeed(feed, originalUrl) {
    // Ensure required fields
    feed.url = feed.url || originalUrl;
    feed.title = feed.title || 'Untitled Feed';
    feed.items = feed.items || [];
    
    // Process items
    feed.items = feed.items.map((item, index) => {
      // Ensure GUID
      if (!item.guid) {
        item.guid = item.link || `${feed.url}#item-${index}`;
      }
      
      // Normalize dates
      if (item.pubDate) {
        item.publishedAt = new Date(item.pubDate).toISOString();
      } else if (item.published) {
        item.publishedAt = new Date(item.published).toISOString();
      } else {
        item.publishedAt = new Date().toISOString();
      }
      
      // Clean and limit description
      if (item.description) {
        item.description = this.stripHtml(item.description).substring(0, 500);
      } else if (item.summary) {
        item.description = this.stripHtml(item.summary).substring(0, 500);
      } else if (item.content) {
        item.description = this.stripHtml(item.content).substring(0, 500);
      }
      
      // Extract first image if no thumbnail
      if (!item.thumbnail && !item.image && item.content) {
        const imgMatch = item.content.match(/<img[^>]+src=["']([^"']+)["']/i);
        if (imgMatch) {
          item.thumbnail = imgMatch[1];
        }
      }
      
      return item;
    });
    
    // Sort items by date (newest first)
    feed.items.sort((a, b) => 
      new Date(b.publishedAt).getTime() - new Date(a.publishedAt).getTime()
    );
    
    // Add metadata
    feed.itemCount = feed.items.length;
    feed.lastUpdated = feed.items[0]?.publishedAt || new Date().toISOString();
    
    return feed;
  }

  // Strip HTML tags from text
  stripHtml(html) {
    const tmp = document.createElement('div');
    tmp.innerHTML = html;
    return tmp.textContent || tmp.innerText || '';
  }

  // Test feed URL without fully parsing
  async testFeed(url) {
    try {
      const response = await this.fetchFeed(url, { timeout: 10000 });
      const text = await response.text();
      
      // Quick validation
      if (text.includes('<rss') || text.includes('<feed') || text.includes('"version"')) {
        return { valid: true, url };
      }
      
      return { valid: false, error: 'Not a valid feed format' };
    } catch (error) {
      return { valid: false, error: error.message };
    }
  }

  // Get feed favicon
  async getFeedFavicon(feed) {
    try {
      const siteUrl = feed.siteUrl || feed.url;
      const url = new URL(siteUrl);
      
      // Try common favicon locations
      const faviconUrls = [
        `${url.origin}/favicon.ico`,
        `${url.origin}/favicon.png`,
        `${url.origin}/apple-touch-icon.png`
      ];
      
      for (const faviconUrl of faviconUrls) {
        try {
          const response = await fetch(faviconUrl, { method: 'HEAD' });
          if (response.ok) {
            return faviconUrl;
          }
        } catch (e) {
          // Continue to next URL
        }
      }
      
      // Use Google's favicon service as fallback
      return `https://www.google.com/s2/favicons?domain=${url.hostname}&sz=32`;
    } catch (error) {
      return null;
    }
  }
}

// Export for use in extension
const feedParser = new FeedParser();