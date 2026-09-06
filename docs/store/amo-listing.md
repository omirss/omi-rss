# Firefox Add-ons (AMO) listing — Omi RSS Reader

Everything needed to submit at addons.mozilla.org. Version at time of writing:
0.5.0. Gecko id is already baked into the Firefox manifest:
{41a6adaa-f9f6-429c-b579-48e0f0697dfe} (strict_min_version 109).

## Name

Omi RSS Reader

## Short summary (127 of 250 chars allowed)

Save articles from any page, follow RSS feeds, and read them in a private popup reader. Local-first, no tracking.

## Full description (plain text, paste as-is)

Omi RSS Reader is a local-first RSS reader and article saver that lives in your
browser. Follow the sites you care about, save anything worth keeping, and read
it all from a fast popup.

READ AND SAVE
- Read feeds in the toolbar popup
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

## Categories

Primary: Feeds, News & Reading (select "Feeds, News & Reading" / News & Reading
family if the picker splits them; fallback News & Weather equivalent is not
used on AMO).

## Language

English (en-US)

## Privacy policy

AMO requires a privacy policy URL for add-ons with host permissions. If the
project site does not host one yet, the same text as the CWS privacy section
(cws-listing.md) can be published on the project site and linked. Minimum
required statement is covered by the declarations below.

## Data-collection disclosures (AMO wizard)

- Authentication information: stored locally, used only to sign in to the
  user-configured self-hosted Omi RSS server. Not transferred elsewhere.
- Website content: article/feed content the user saves or subscribes to,
  processed to provide the reading experience. Kept local (and on the user's
  own server when paired).
- No health, financial, location, or browsing-history collection.
- No third-party analytics, trackers, or advertising. No sale of data.

## Permission justifications (AMO prompts for these at upload)

| Permission | Justification for the reviewer |
| --- | --- |
| <all_urls> host permissions (http://*/*, https://*/*) | Required for three user-triggered features: feed detection on pages the user visits (Find Feeds), full-text extraction of articles the user saves or subscribes to, and the region picker that turns a chosen page area into a monitored feed. Also allows fetching the user's subscribed feed URLs and reaching the user-configured self-hosted server. The extension never records visited pages and takes no page action unless the user invokes a feature. Broad matching is inherent to the product: feeds and articles live on arbitrary sites. |
| activeTab | Read the current tab when the user triggers save, reader mode, or feed detection. |
| tabs | Query and message the active tab from the event-page background when a command or context-menu action needs the current page. The Chrome build covers this with activeTab; the Firefox event-page architecture needs tabs for the equivalent behavior. No browsing history is retained. |
| scripting | Inject extraction/reader-mode code into the current page on user action. |
| storage | Store settings, subscriptions, saved articles, and server credentials locally. |
| alarms | Schedule background feed refresh. |
| contextMenus | Right-click entries for save and reader mode. |
| notifications | Confirm saves, subscriptions, and refresh results. |
| downloads | Export OPML and JSON backup files the user requests. |

## AMO-specific notes

- Upload extension/build/omi-rss-firefox.zip. The JavaScript is unminified
  source; AMO should not require a source submission. If the reviewer asks,
  point them at the public repository.
- The Firefox manifest swaps sidePanel for tabs and runs an event-page
  background instead of a service worker. The side panel surface itself is
  Chrome-only; on Firefox the reader lives in the popup and pop-out window.
- Listing screenshots are the same set as Chrome (docs/store/screenshots/).
  AMO displays portrait shots well; the padded 1280x800 set works as-is.
