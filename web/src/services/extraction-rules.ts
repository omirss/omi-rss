// Server-side site-specific extraction seeds, ported from
// extension/js/extractors/site-specific.js (same repo, MIT). The extension
// runs these in the browser; here they act as the second rung of the
// extraction fallback ladder (Readability → site selector → meta excerpt)
// and as default item selectors where a site is a list page. Function-based
// processors and client-only pieces (redirects, window.location) are not
// portable and were dropped.

export interface SiteExtractionRules {
  itemSelector?: string;
  titleSelector?: string;
  contentSelector?: string;
}

export const SITE_EXTRACTION_RULES: Record<string, SiteExtractionRules> = {
  "medium.com": {
    titleSelector: "h1",
    contentSelector: "section",
  },
  "substack.com": {
    titleSelector: "h1.post-title",
    contentSelector: ".available-content",
  },
  "nytimes.com": {
    titleSelector: 'h1[data-testid="headline"]',
    contentSelector: 'section[name="articleBody"]',
  },
  "washingtonpost.com": {
    titleSelector: 'h1[data-qa="headline"]',
    contentSelector: '[data-qa="article-body"]',
  },
  "theguardian.com": {
    titleSelector: "h1",
    contentSelector: '[itemprop="articleBody"]',
  },
  "bbc.com": {
    titleSelector: "h1#main-heading",
    contentSelector: '[data-component="text-block"]',
  },
  "techcrunch.com": {
    titleSelector: "h1.article__title",
    contentSelector: ".article-content",
  },
  "theverge.com": {
    titleSelector: "h1",
    contentSelector: ".c-entry-content",
  },
  "arstechnica.com": {
    titleSelector: 'h1[itemprop="headline"]',
    contentSelector: '[itemprop="articleBody"]',
  },
  "news.ycombinator.com": {
    itemSelector: ".titleline > a",
  },
  "reddit.com": {
    titleSelector: "h1",
    contentSelector: '[data-test-id="post-content"]',
  },
  "github.com": {
    titleSelector: ".markdown-body h1",
    contentSelector: ".markdown-body",
  },
  "stackoverflow.com": {
    titleSelector: 'h1[itemprop="name"]',
    contentSelector: ".s-prose",
  },
  "wikipedia.org": {
    titleSelector: "h1.firstHeading",
    contentSelector: "#mw-content-text .mw-parser-output",
  },
  "dev.to": {
    titleSelector: "h1",
    contentSelector: '[id="article-body"]',
  },
  "forbes.com": {
    titleSelector: "h1",
    contentSelector: ".article-body",
  },
  "bloomberg.com": {
    titleSelector: "h1",
    contentSelector: ".body-content",
  },
};

export function findExtractionRules(hostname: string): SiteExtractionRules | null {
  const host = hostname.toLowerCase();
  for (const [pattern, rules] of Object.entries(SITE_EXTRACTION_RULES)) {
    if (host === pattern || host.endsWith(`.${pattern}`)) {
      return rules;
    }
  }
  return null;
}
