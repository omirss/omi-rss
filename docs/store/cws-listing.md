# Chrome Web Store listing — Omi RSS Reader

Everything needed to fill in the CWS developer dashboard form. Copy fields
verbatim. Version at time of writing: 0.5.0.

## Name

Omi RSS Reader

## Short summary (127 of 132 chars allowed)

Save articles from any page, follow RSS feeds, and read them in a private popup or side panel reader. Local-first, no tracking.

## Full description (plain text, paste as-is)

Omi RSS Reader is a local-first RSS reader and article saver that lives in your
browser. Follow the sites you care about, save anything worth keeping, and read
it all from a fast popup or a persistent side panel.

READ AND SAVE
- Read feeds in the toolbar popup or the Chrome side panel
- Save any article from the page you are on: toolbar button, context menu, or
  Ctrl+Shift+S (Command+Shift+S on Mac)
- Reader mode (Ctrl+Shift+R, Command+Shift+R on Mac) strips the page down to
  clean article text, with per-site extraction rules for stubborn sites
- Star articles to a Saved list for later
- If an article disappears, one-click fallback links open it on archive.org or
  archive.today

SUBSCRIBE
- Find Feeds detects RSS feeds on pages you visit and subscribes in one click
- Add any feed by URL
- Optional full-text mode per feed: the server fetches and extracts complete
  article text, not just the snippet the feed provides
- Generate a feed from any page: pick a content region with the region picker
  and the page is monitored as a durable feed with live item preview (requires
  a paired server)

WORKS THE WAY YOU RUN YOUR DATA
- Local-first: subscriptions, saved articles, and settings live in your
  browser, with offline storage (IndexedDB) and a sync queue
- Optional pairing with a self-hosted Omi RSS server for sync, OPML
  import/export, and full-text extraction. The server URL is user-configured;
  nothing points at a vendor cloud by default
- JSON backup export/import works as a file-based sync between machines
- Light and dark themes follow your system

Omi RSS Reader collects no analytics, includes no trackers, and sells no data.
Content scripts run only to detect feeds and extract article content you
explicitly save or subscribe to.

## Category

News & Weather

## Language

English (en)

## Privacy

### Single-purpose statement

Omi RSS Reader detects RSS feeds on web pages, saves and extracts article
content at the user's request, and displays the user's feed subscriptions and
saved articles in a reader.

### Permission justifications

| Permission | Justification |
| --- | --- |
| Host permissions (http://*/*, https://*/*) and content script on <all_urls> | Three user-triggered purposes: (1) feed detection on pages the user visits so Find Feeds can offer one-click subscribe; (2) full-text content extraction of pages the user saves or subscribes to with full text enabled; (3) the region picker that turns a chosen page area into a monitored feed. Host access also lets the background scheduler fetch the feed URLs the user subscribed to and call the user-configured self-hosted server URL. The extension does not collect browsing history and takes no action on a page unless the user invokes a feature. |
| activeTab | Read the current tab's title, URL, and content when the user clicks save, reader mode, or feed detection. |
| scripting | Inject the extraction/reader-mode code into the current page on user action. |
| storage | Store settings, subscriptions, saved articles, and credentials locally in the browser. |
| alarms | Schedule background feed refresh for subscribed feeds. |
| contextMenus | Offer Save article and reader-mode entries in the right-click menu. |
| notifications | Confirm saves, subscriptions, and refresh results. |
| sidePanel | Open the reader as a Chrome side panel. |
| downloads | Export OPML and JSON backup files the user requests. |

### Data usage declarations (CWS privacy tab)

- Authentication information: used only to sign in to the user-configured,
  self-hosted Omi RSS server. Not transferred to any other party. Declared
  because paired-server credentials are stored locally.
- Website content: article text and feed content the user saves or subscribes
  to, processed to provide the reading experience. Stored locally (and on the
  user's own server when paired). Not used for any unrelated purpose.
- Personal communications: not collected.
- Health: not collected. Financial: not collected. Location: not collected.
  Browsing history: not collected (content scripts act only on user command;
  no record of visited pages is retained).
- Data sold to third parties: no.
- Data used for creditworthiness or lending: no.
- Data used for third-party advertising or advertising-related purposes: no.
- Third-party analytics or tracking: none. No analytics SDKs or trackers are
  bundled. Local reading statistics, when shown, are computed and displayed
  locally for the user only.
- Data security: all data stays in browser-local storage or, when the user
  pairs a server, on that user-chosen self-hosted instance.

### Certified developer-privacy claims

- No sale of data: yes.
- No use of data for third-party advertising: yes.
- No use of data for creditworthiness: yes.
