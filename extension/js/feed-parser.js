// Local RSS/Atom/JSON Feed Parser for Browser Extension
class FeedParser {
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

  // Fetch feed content. Extension contexts with host_permissions fetch
  // cross-origin without CORS; failures propagate to parseFeed's catch.
  // The abort timer stays armed through the BODY read and the body is
  // streamed under a hard 5 MiB cap, so a server that sends headers then
  // stalls, or streams forever, cannot pin the scheduler slot or buffer
  // unbounded memory.
  async fetchFeed(url, options = {}) {
    const { timeout = 30000 } = options;
    const maxBytes = 5 * 1024 * 1024;

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeout);

    try {
      const response = await fetch(url, {
        signal: controller.signal,
        headers: {
          'Accept': 'application/rss+xml, application/atom+xml, application/json, text/xml, */*'
        }
      });

      if (!response.ok) {
        try { await response.body?.cancel(); } catch (err) { /* already released */ }
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const reader = response.body ? response.body.getReader() : null;
      if (!reader) {
        return response;
      }

      const chunks = [];
      let total = 0;
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        total += value.byteLength;
        if (total > maxBytes) {
          await reader.cancel().catch(() => {});
          throw new Error(`Feed body exceeded ${maxBytes} bytes`);
        }
        chunks.push(value);
      }

      return new Response(new Blob(chunks), {
        status: response.status,
        headers: response.headers
      });
    } catch (error) {
      if (error && error.name === 'AbortError') {
        throw new Error(`Feed fetch timed out after ${timeout}ms`);
      }
      throw error;
    } finally {
      clearTimeout(timeoutId);
    }
  }

  // Parse XML feeds (RSS/Atom)
  async parseXMLFeed(xmlText, feedUrl) {
    // Service workers have no DOMParser - fall back to a text-based parser
    if (typeof DOMParser === 'undefined') {
      return this.parseXMLFeedText(xmlText, feedUrl);
    }

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

  // Text-based RSS/Atom parsing for environments without DOMParser
  parseXMLFeedText(xmlText, feedUrl) {
    const isAtom = /<feed[\s>]/i.test(xmlText) && !/<rss[\s>]/i.test(xmlText);

    const pick = (block, tag) => {
      const match = block.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`, 'i'));
      return match ? this.decodeXmlEntities(match[1].replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').trim()) : null;
    };

    const readBlocks = (containerText, tag) => {
      const blocks = [];
      const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`, 'gi');
      let match;
      while ((match = re.exec(containerText)) !== null) {
        blocks.push(match[1]);
      }
      return blocks;
    };

    let feed;

    if (isAtom) {
      // Feed-level links live before the first <entry>; Atom links are
      // self-closing so paired-tag matching never finds them.
      const head = xmlText.split(/<entry[\s>]/i)[0];
      const siteLink = this.getAtomTextLink(head, feedUrl);
      feed = {
        type: 'atom',
        title: pick(xmlText, 'title'),
        description: pick(xmlText, 'subtitle') || '',
        url: feedUrl,
        siteUrl: siteLink || feedUrl,
        items: []
      };

      for (const entry of readBlocks(xmlText, 'entry')) {
        const link = this.getAtomTextLink(entry, feedUrl);
        feed.items.push({
          guid: pick(entry, 'id') || link || '',
          title: pick(entry, 'title') || 'Untitled',
          link: link || '',
          summary: pick(entry, 'summary') || '',
          content: pick(entry, 'content') || '',
          published: pick(entry, 'published') || pick(entry, 'updated') || null,
          updated: pick(entry, 'updated') || null
        });
      }
    } else {
      const channelMatch = xmlText.match(/<channel[^>]*>([\s\S]*?)<\/channel>/i);
      const channel = channelMatch ? channelMatch[1] : xmlText;

      feed = {
        type: 'rss',
        title: pick(channel, 'title'),
        description: pick(channel, 'description') || '',
        url: feedUrl,
        siteUrl: pick(channel, 'link') || feedUrl,
        items: []
      };

      for (const item of readBlocks(channel, 'item')) {
        const contentEncoded = pick(item, 'content:encoded');
        feed.items.push({
          guid: pick(item, 'guid') || pick(item, 'link') || '',
          title: pick(item, 'title') || 'Untitled',
          link: pick(item, 'link') || '',
          description: pick(item, 'description') || '',
          content: contentEncoded || '',
          pubDate: pick(item, 'pubDate') || null,
          author: pick(item, 'author') || pick(item, 'dc:creator') || ''
        });
      }
    }

    if (!feed.title) {
      throw new Error('Unknown XML feed format');
    }

    return feed;
  }

  // Decode common XML entities
  decodeXmlEntities(text) {
    return text
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;|&apos;/g, "'")
      .replace(/&amp;/g, '&');
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
    
    // Extract content; type="xhtml" content keeps its markup (it is a
    // serialized div per RFC 4287) instead of being flattened to text.
    const content = entry.querySelector('content');
    if (content) {
      article.content = content.getAttribute('type') === 'xhtml'
        ? content.innerHTML
        : content.textContent || '';
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
  // Namespaced tags (dc:creator, content:encoded, media:*) are invalid CSS
  // selectors in XML documents, so match them by local/qualified name instead.
  getTextContent(parent, selector) {
    let element;
    if (selector.includes(':')) {
      const localName = selector.split(':')[1];
      element = parent.getElementsByTagNameNS('*', localName)[0] ||
        parent.getElementsByTagName(selector)[0];
    } else {
      element = parent.querySelector(selector);
    }
    return element?.textContent?.trim() || null;
  }

  // Helper: Get Atom link. Only DIRECT link children count, and a missing
  // rel means 'alternate' per RFC 4287 — an entry without its own link
  // must not inherit one nested inside its content.
  getAtomLink(parent, rel) {
    for (const child of parent.children) {
      if (!child.tagName || child.tagName.toLowerCase() !== 'link') continue;
      if ((child.getAttribute('rel') || 'alternate') === rel && child.getAttribute('href')) {
        return child.getAttribute('href');
      }
    }
    return null;
  }

  // Text-mode Atom link extraction (service workers have no DOMParser):
  // prefers the alternate link, resolves against the feed URL.
  getAtomTextLink(blockText, baseUrl) {
    const linkTags = [];
    const re = /<link\b[^>]*>/gi;
    let match;
    while ((match = re.exec(blockText)) !== null) {
      linkTags.push(match[0]);
    }
    let fallback = null;
    for (const tag of linkTags) {
      const href = tag.match(/href=["']([^"']+)["']/i);
      if (!href) continue;
      const rel = tag.match(/rel=["']([^"']+)["']/i);
      if (!rel || rel[1] === 'alternate') {
        return this.resolveUrl(href[1], baseUrl);
      }
      if (!fallback) fallback = href[1];
    }
    return fallback ? this.resolveUrl(fallback, baseUrl) : null;
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

      // Normalize dates - one invalid pubDate must not throw a RangeError
      // that discards every valid item in the feed; it falls back to
      // arrival time per item.
      const rawDate = item.pubDate || item.published || item.publishedAt;
      const parsedDate = rawDate ? new Date(rawDate) : new Date();
      item.publishedAt = (parsedDate && Number.isFinite(parsedDate.getTime()) ? parsedDate : new Date()).toISOString();

      // Resolve relative item links against the feed URL.
      if (item.link) {
        item.link = this.resolveUrl(item.link, feed.url);
      }

      // Description stays HTML like content: rendering goes through the
      // same sanitizer walker. Backfill it from summary/content when the
      // feed only provides those, and derive a plain-text excerpt for cards.
      if (!item.description) {
        item.description = item.summary || item.content || '';
      }

      // Resolve relative img srcs against the feed URL FIRST: any later
      // parse of the HTML (stripHtml below builds a detached innerHTML -
      // Chrome still fetches its imgs) must hit the feed origin, never the
      // chrome-extension:// page origin
      item.content = this.resolveImgSrcs(item.content, feed.url);
      item.description = this.resolveImgSrcs(item.description, feed.url);

      item.excerpt = this.stripHtml(item.description || item.summary || item.content || '')
        .substring(0, 500);

      // Extract first image if no thumbnail
      if (!item.thumbnail && !item.image) {
        const imgHtml = item.content || item.description;
        const imgMatch = imgHtml && imgHtml.match(/<img[^>]+src=["']([^"']+)["']/i);
        if (imgMatch) {
          item.thumbnail = this.resolveUrl(imgMatch[1], feed.url);
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
    if (typeof document !== 'undefined') {
      const tmp = document.createElement('div');
      tmp.innerHTML = html;
      return tmp.textContent || tmp.innerText || '';
    }
    return String(html)
      .replace(/<script[\s\S]*?<\/script>/gi, '')
      .replace(/<style[\s\S]*?<\/style>/gi, '')
      .replace(/<[^>]+>/g, ' ')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/\s+/g, ' ')
      .trim();
  }

  // Resolve a possibly-relative URL against a base URL
  resolveUrl(src, baseUrl) {
    try {
      return new URL(src, baseUrl).toString();
    } catch (error) {
      return src;
    }
  }

  // Resolve every <img src> in an HTML string against a base URL
  resolveImgSrcs(html, baseUrl) {
    if (!html) return html;
    return html.replace(/(<img[^>]+src=["'])([^"']+)(["'])/gi, (match, pre, src, post) =>
      pre + this.resolveUrl(src, baseUrl) + post
    );
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
      
      // HEAD can fail (e.g. 405) while GET works; fall back to the origin
      return `${url.origin}/favicon.ico`;
    } catch (error) {
      return null;
    }
  }
}

// Export for use in extension
const feedParser = new FeedParser();

// Exported for the node test runner only; extension contexts load this
// file as a classic script where feedParser is a plain global.
if (typeof module !== 'undefined') {
  module.exports = { FeedParser, feedParser };
}