// RSSHub Route Examples

const got = require('got');
const cheerio = require('cheerio');
const { parseDate } = require('./utils');

// Twitter/X Route Example
module.exports = {
  '/twitter/user/:username': {
    name: 'Twitter User Timeline',
    example: '/twitter/user/elonmusk',
    parameters: {
      username: 'Twitter username without @'
    },
    features: {
      requireConfig: false,
      requirePuppeteer: true,
      antiCrawler: true,
      supportBT: false,
      supportPodcast: false,
      supportScihub: false
    },
    radar: {
      source: ['twitter.com/:username', 'x.com/:username'],
      target: '/twitter/user/:username'
    },
    handler: async (ctx) => {
      const username = ctx.params.username;
      const baseUrl = 'https://twitter.com';
      
      // Use puppeteer for JavaScript-heavy site
      const browser = await require('./puppeteer')();
      const page = await browser.newPage();
      
      // Set user agent to avoid detection
      await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
      
      // Navigate to user timeline
      await page.goto(`${baseUrl}/${username}`, {
        waitUntil: 'networkidle2',
        timeout: 30000
      });
      
      // Wait for tweets to load
      await page.waitForSelector('article[data-testid="tweet"]', {
        timeout: 10000
      });
      
      // Extract tweets
      const tweets = await page.evaluate(() => {
        const tweetElements = document.querySelectorAll('article[data-testid="tweet"]');
        const tweets = [];
        
        tweetElements.forEach((tweet, index) => {
          if (index >= 20) return; // Limit to 20 tweets
          
          const textElement = tweet.querySelector('div[data-testid="tweetText"]');
          const timeElement = tweet.querySelector('time');
          const linkElement = tweet.querySelector('a[href*="/status/"]');
          
          if (textElement && timeElement && linkElement) {
            const text = textElement.innerText;
            const timestamp = timeElement.getAttribute('datetime');
            const link = linkElement.getAttribute('href');
            
            // Extract images
            const images = [];
            tweet.querySelectorAll('img[alt="Image"]').forEach(img => {
              images.push(img.src);
            });
            
            tweets.push({
              title: text.substring(0, 100) + (text.length > 100 ? '...' : ''),
              description: text,
              link: `https://twitter.com${link}`,
              pubDate: new Date(timestamp),
              author: `@${username}`,
              images
            });
          }
        });
        
        return tweets;
      });
      
      await browser.close();
      
      // Return RSS format
      ctx.state.data = {
        title: `${username} - Twitter`,
        link: `${baseUrl}/${username}`,
        description: `Twitter timeline for @${username}`,
        item: tweets.map(tweet => ({
          title: tweet.title,
          description: tweet.description + (tweet.images.length > 0 
            ? '<br><br>' + tweet.images.map(img => `<img src="${img}">`).join('')
            : ''),
          link: tweet.link,
          pubDate: tweet.pubDate,
          author: tweet.author
        }))
      };
    }
  },
  
  // GitHub Repository Route Example
  '/github/:owner/:repo/:type?': {
    name: 'GitHub Repository',
    example: '/github/flutter/flutter/releases',
    parameters: {
      owner: 'Repository owner',
      repo: 'Repository name',
      type: 'Type: releases, commits, issues, pulls'
    },
    features: {
      requireConfig: false,
      requirePuppeteer: false,
      antiCrawler: false
    },
    handler: async (ctx) => {
      const { owner, repo, type = 'releases' } = ctx.params;
      const baseUrl = `https://github.com/${owner}/${repo}`;
      
      let items = [];
      
      switch (type) {
        case 'releases':
          const releasesUrl = `${baseUrl}/releases.atom`;
          const releasesResponse = await got(releasesUrl);
          // Parse Atom feed directly
          const $ = cheerio.load(releasesResponse.body, { xmlMode: true });
          
          $('entry').each((_, elem) => {
            const $elem = $(elem);
            items.push({
              title: $elem.find('title').text(),
              description: $elem.find('content').text(),
              link: $elem.find('link').attr('href'),
              pubDate: parseDate($elem.find('updated').text()),
              author: $elem.find('author name').text()
            });
          });
          break;
          
        case 'commits':
          const commitsUrl = `${baseUrl}/commits/main.atom`;
          const commitsResponse = await got(commitsUrl);
          const $commits = cheerio.load(commitsResponse.body, { xmlMode: true });
          
          $commits('entry').each((_, elem) => {
            const $elem = $commits(elem);
            items.push({
              title: $elem.find('title').text(),
              description: `<pre>${$elem.find('content').text()}</pre>`,
              link: $elem.find('link').attr('href'),
              pubDate: parseDate($elem.find('updated').text()),
              author: $elem.find('author name').text()
            });
          });
          break;
          
        case 'issues':
          // Use GitHub API for issues
          const issuesUrl = `https://api.github.com/repos/${owner}/${repo}/issues`;
          const issuesResponse = await got(issuesUrl, {
            headers: {
              'Accept': 'application/vnd.github.v3+json',
              'User-Agent': 'RSSHub'
            }
          });
          
          const issues = JSON.parse(issuesResponse.body);
          items = issues.slice(0, 20).map(issue => ({
            title: `#${issue.number}: ${issue.title}`,
            description: issue.body || 'No description',
            link: issue.html_url,
            pubDate: parseDate(issue.created_at),
            author: issue.user.login
          }));
          break;
      }
      
      ctx.state.data = {
        title: `${owner}/${repo} - ${type}`,
        link: baseUrl,
        description: `GitHub ${type} for ${owner}/${repo}`,
        item: items
      };
    }
  },
  
  // Reddit Subreddit Route Example
  '/reddit/subreddit/:subreddit/:sort?': {
    name: 'Reddit Subreddit',
    example: '/reddit/subreddit/programming/hot',
    parameters: {
      subreddit: 'Subreddit name',
      sort: 'Sort type: hot, new, top, rising'
    },
    handler: async (ctx) => {
      const { subreddit, sort = 'hot' } = ctx.params;
      const url = `https://www.reddit.com/r/${subreddit}/${sort}.json`;
      
      const response = await got(url, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; RSSHub)'
        }
      });
      
      const data = JSON.parse(response.body);
      const posts = data.data.children;
      
      const items = posts.map(post => {
        const postData = post.data;
        return {
          title: postData.title,
          description: `
            ${postData.selftext_html ? postData.selftext_html : ''}
            ${postData.url && !postData.is_self ? `<br><a href="${postData.url}">${postData.url}</a>` : ''}
            <br><br>
            👍 ${postData.ups} | 💬 ${postData.num_comments} comments
          `,
          link: `https://reddit.com${postData.permalink}`,
          pubDate: new Date(postData.created_utc * 1000),
          author: `/u/${postData.author}`,
          category: postData.link_flair_text
        };
      });
      
      ctx.state.data = {
        title: `/r/${subreddit} - ${sort}`,
        link: `https://reddit.com/r/${subreddit}`,
        description: `Reddit posts from /r/${subreddit}`,
        item: items
      };
    }
  },
  
  // YouTube Channel Route Example
  '/youtube/channel/:id': {
    name: 'YouTube Channel',
    example: '/youtube/channel/UCddiUEpeqJcYeBxX1IVBKvQ',
    parameters: {
      id: 'Channel ID'
    },
    features: {
      requirePuppeteer: true,
      antiCrawler: true
    },
    handler: async (ctx) => {
      const channelId = ctx.params.id;
      const channelUrl = `https://www.youtube.com/channel/${channelId}/videos`;
      
      const browser = await require('./puppeteer')();
      const page = await browser.newPage();
      
      await page.goto(channelUrl, {
        waitUntil: 'networkidle2'
      });
      
      // Scroll to load more videos
      await page.evaluate(() => {
        return new Promise((resolve) => {
          let totalHeight = 0;
          const distance = 100;
          const timer = setInterval(() => {
            const scrollHeight = document.body.scrollHeight;
            window.scrollBy(0, distance);
            totalHeight += distance;
            
            if (totalHeight >= scrollHeight) {
              clearInterval(timer);
              resolve();
            }
          }, 100);
        });
      });
      
      // Extract video data
      const videos = await page.evaluate(() => {
        const videoElements = document.querySelectorAll('#video-title');
        const videos = [];
        
        videoElements.forEach((elem, index) => {
          if (index >= 20) return;
          
          const link = elem.href;
          const title = elem.textContent.trim();
          const thumbnail = elem.closest('#dismissible').querySelector('img').src;
          
          // Extract video ID from URL
          const videoId = link.match(/v=([^&]+)/)?.[1];
          
          videos.push({
            title,
            link,
            videoId,
            thumbnail
          });
        });
        
        return videos;
      });
      
      await browser.close();
      
      // Transform to RSS items
      const items = videos.map(video => ({
        title: video.title,
        description: `
          <img src="${video.thumbnail}" /><br>
          <a href="${video.link}">Watch on YouTube</a><br><br>
          <iframe width="560" height="315" 
            src="https://www.youtube.com/embed/${video.videoId}" 
            frameborder="0" allowfullscreen></iframe>
        `,
        link: video.link,
        guid: video.videoId
      }));
      
      ctx.state.data = {
        title: `YouTube Channel - ${channelId}`,
        link: channelUrl,
        description: 'Latest videos from YouTube channel',
        item: items
      };
    }
  },
  
  // Generic Website Route Example
  '/website/generic': {
    name: 'Generic Website Parser',
    example: '/website/generic?url=https://example.com',
    parameters: {
      url: 'Website URL to parse'
    },
    handler: async (ctx) => {
      const targetUrl = ctx.query.url;
      if (!targetUrl) {
        throw new Error('URL parameter is required');
      }
      
      const response = await got(targetUrl);
      const $ = cheerio.load(response.body);
      
      // Try to detect feed items using common patterns
      const selectors = [
        'article',
        '.post',
        '.entry',
        '.item',
        '[itemtype*="Article"]',
        '.blog-post',
        '.news-item'
      ];
      
      let items = [];
      
      for (const selector of selectors) {
        const elements = $(selector);
        if (elements.length > 0) {
          elements.each((index, elem) => {
            if (index >= 20) return;
            
            const $elem = $(elem);
            
            // Extract title
            const title = $elem.find('h1, h2, h3, h4').first().text().trim() ||
                         $elem.find('a').first().text().trim();
            
            // Extract link
            const link = $elem.find('a').first().attr('href');
            const absoluteLink = link ? new URL(link, targetUrl).href : targetUrl;
            
            // Extract description
            const description = $elem.find('p').first().text().trim() ||
                              $elem.find('.summary, .excerpt').text().trim();
            
            // Extract date
            const dateText = $elem.find('time').attr('datetime') ||
                           $elem.find('.date, .published').text().trim();
            const pubDate = dateText ? parseDate(dateText) : new Date();
            
            if (title) {
              items.push({
                title,
                description,
                link: absoluteLink,
                pubDate
              });
            }
          });
          
          if (items.length > 0) break;
        }
      }
      
      // Extract site metadata
      const siteTitle = $('title').text() || 
                       $('meta[property="og:title"]').attr('content') ||
                       'Generated Feed';
      
      const siteDescription = $('meta[name="description"]').attr('content') ||
                            $('meta[property="og:description"]').attr('content') ||
                            '';
      
      ctx.state.data = {
        title: siteTitle,
        link: targetUrl,
        description: siteDescription,
        item: items
      };
    }
  }
};