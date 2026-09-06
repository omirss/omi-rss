# Store submission checklist — Tyler's manual steps

Everything else is prepared. Zip packages, listing copy, and screenshots are
done; this is the click-through list.

## Assets on disk

| Asset | Path (relative to app/) |
| --- | --- |
| Chrome zip (upload this) | extension/build/omi-rss-chrome.zip |
| Firefox zip (upload this) | extension/build/omi-rss-firefox.zip |
| CWS listing copy | docs/store/cws-listing.md |
| AMO listing copy | docs/store/amo-listing.md |
| Screenshots (1280x800, 5) | docs/store/screenshots/01-reader-webui.png ... 05-page-feed-picker.png |
| Small promo tile 440x280 | NOT PREPARED — optional for CWS, needed only for featured placement. Generate from extension/icons/icon.svg if wanted. |

Screenshot meanings: 01 reader web UI (server-paired home), 02 popup article
view, 03 side panel (dark), 04 Find Feeds subscribe modal, 05 page-to-feed
region picker with confirm bar. All are letterboxed to exactly 1280x800 on a
neutral background; no content was stretched.

## Chrome Web Store

1. One-time: register at https://chrome.google.com/webstore/devconsole
   (Google account, one-time $5 fee).
2. New item -> Upload -> extension/build/omi-rss-chrome.zip.
3. Store listing tab, mapped to docs/store/cws-listing.md:
   - Name, short summary, description: copy verbatim.
   - Category: News & Weather. Language: English.
   - Screenshots: upload all 5 from docs/store/screenshots/ (1280x800 each,
     minimum required size; max 5 shown on the listing).
   - Small promo tile 440x280: optional; skip unless you make one.
   - Extension icon: pulled automatically from the zip.
4. Privacy tab: single-purpose statement and permission justifications from
   cws-listing.md; answer the data-usage declarations exactly as listed
   (no sale, no ads, no analytics; auth info + website content only, local /
   user's own server).
5. If asked for a privacy policy URL: publish the privacy section on the
   project site first, then link it (currently a gap — see below).
6. Distribution: Public. Regions: all.
7. Submit for review. Broad host permissions (<all_urls>) mean a human review;
   expect several days and a possible request for a demo video or
   justification — the permission table in cws-listing.md is the answer text.

## Firefox Add-ons (AMO)

1. One-time: register at https://addons.mozilla.org/developers/ (free).
2. Submit a New Add-on -> Upload -> extension/build/omi-rss-firefox.zip
   (On your own, self-distribution not needed; aim for listed).
3. AMO shows a source-code step: not required, JS is unminified. If asked,
   link the public repository.
4. Listing details from docs/store/amo-listing.md: name, summary,
   description, categories, language en-US.
5. Upload the same 5 screenshots.
6. Data-collection wizard: answer per amo-listing.md (auth info + website
   content, everything else no).
7. Permission justification prompts at upload: paste the table rows from
   amo-listing.md.
8. Privacy policy URL required for host-permission add-ons — same gap as CWS
   (see below).
9. Submit. AMO review is typically 1-5 days; automatic signing is immediate
   afterward.

## Known gaps (decide before submitting)

- Privacy policy URL: neither store has a hosted policy page yet. Publish the
  privacy section of cws-listing.md on the project site (or a static page) and
  paste the URL in both dashboards.
- Promo tile 440x280 (CWS, optional).
- No demo video prepared; only needed if a reviewer requests one.

## After approval

- Record store IDs/URLs in the project README.
- Bump versions via the manifests (chrome + firefox) and rebuild with
  ./build.sh from inside extension/ before re-uploading.
