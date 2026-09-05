import { describe, it, expect } from "vitest";
import { h } from "preact";
import render from "preact-render-to-string";
import { ReaderView } from "../components/reading/ReaderView.js";
import { ToastProvider } from "../components/Toast.js";
import type { ArticleListItem } from "../lib/api-types.js";

// Reader footer archive-fallback links: pure anchors to web.archive.org /
// archive.ph, target _blank rel noopener, only when the article has a URL.

const article: ArticleListItem = {
  id: "a1",
  feedId: "f1",
  title: "Title",
  url: "https://example.com/post/1",
  summary: null,
  content: null,
  author: null,
  publishedAt: "2026-01-01T00:00:00.000Z",
  imageUrl: null,
  enclosures: [],
  isRead: false,
  isStarred: false,
  readAt: null,
  feedTitle: "Feed",
  feedFavicon: null,
};

function renderReader(articles: ArticleListItem[]): string {
  return render(
    h(ToastProvider, null,
      h(ReaderView, {
        articles,
        index: 0,
        onIndexChange: () => undefined,
        onClose: () => undefined,
        onMarkRead: () => undefined,
        onToggleStar: () => false,
      }),
    ),
  );
}

describe("ReaderView archive links", () => {
  it("renders archive.org and archive.today links with correct hrefs", () => {
    const html = renderReader([article]);

    expect(html).toContain('href="https://web.archive.org/web/https://example.com/post/1"');
    expect(html).toContain('href="https://archive.ph/newest/https://example.com/post/1"');
  });

  it("opens them in a new tab with noopener", () => {
    const html = renderReader([article]);

    const archiveOrg = html.slice(html.indexOf("web.archive.org") - 30, html.indexOf("web.archive.org") + 120);
    expect(archiveOrg).toContain('target="_blank"');
    expect(archiveOrg).toContain('rel="noopener noreferrer"');
  });

  it("omits the archive links when the article has no URL", () => {
    const html = renderReader([{ ...article, url: "" }]);

    expect(html).not.toContain("web.archive.org");
    expect(html).not.toContain("archive.ph");
  });
});
