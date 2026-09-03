# Omi RSS Browser Extension

Browser extension companion to Omi RSS: save articles from any webpage, detect
and subscribe to RSS feeds, and read your feeds from the popup or side panel.

Works standalone (local-first, data in browser storage) or paired with a
self-hosted Omi RSS server for sync.

## Features

- Popup reader with feed list, articles, and settings
- Chrome side panel for persistent reading
- Save articles from any page (button, context menu, or Ctrl/Cmd+Shift+S)
- Reader mode (Ctrl/Cmd+Shift+R) with per-site extraction rules
- Feed detection and one-click subscribe
- Offline storage (IndexedDB) with a sync queue
- Export/import backup as JSON file

## Install (development)

### Chrome / Edge / Brave

1. Open `chrome://extensions`
2. Enable Developer mode
3. Load unpacked: select this `extension/` folder

### Firefox

1. Open `about:debugging#/runtime/this-firefox`
2. Load Temporary Add-on: select `manifest_firefox.json`

## Build

```bash
./build.sh
```

Produces `build/chrome/` and `build/firefox/` plus store-ready zip archives.
The Chrome build also works in Brave and Edge as-is.

## Files

- `manifest.json` — Chrome/Chromium (MV3)
- `manifest_firefox.json` — Firefox (MV3, event page)
- `popup.html` + `js/popup.js` — toolbar popup
- `sidepanel.html` + `js/sidepanel-local.js` — side panel reader
- `js/background.js` — service worker: context menus, commands, message router
- `js/api.js` — server API client
- `js/feed-parser.js`, `js/feed-scheduler.js` — feed parsing and refresh timers
- `js/storage-service.js`, `js/offline-db.js` — local data layer
- `js/sync-service.js`, `js/sync-manager.js`, `js/file-sync.js` — sync and backup
- `js/content.js`, `js/extractors/site-specific.js` — in-page actions

## Status

Alpha. Server pairing (login, subscribe-to-server) is being repaired; see the
repository PLAN.md for current phase.
