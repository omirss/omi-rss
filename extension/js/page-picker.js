// On-demand page-feed picker for Omi RSS.
// Injected via chrome.scripting.executeScript from the background when the
// user activates "Generate feed from this page" (popup button or context
// menu). Runs in the content-script isolated world. Not listed in
// manifest content_scripts: it loads only when needed.
//
// Flow: pick mode (hover outline, Esc cancels, click selects) -> confirm bar
// (editable item selector + live match count + title) -> Subscribe posts to
// the server via the background (POST /api/feeds/page). Page feeds require a
// server connection; without one the bar says so instead of pretending.

(() => {
  if (window.__omiPagePickerLoaded) {
    window.__omiPagePickerStart();
    return;
  }
  window.__omiPagePickerLoaded = true;

  const ROOT_ID = 'omi-page-picker-root';
  const Z_TOP = 2147483600;

  // 'off' | 'picking' | 'confirm' | 'busy'
  let state = 'off';
  let hovered = null;
  let selected = null;
  let serverAvailable = null;
  let matchTimer = null;
  let teardownTimer = null;

  const cssEscape = (value) => {
    try {
      return CSS.escape(value);
    } catch (err) {
      return String(value).replace(/[^a-zA-Z0-9_-]/g, (c) => `\\${c}`);
    }
  };

  // Classes that look machine-generated (css-in-js hashes, framework junk)
  // make brittle selectors; skip them when building tag.class segments.
  const UNSTABLE_CLASS_RE = /^(?:js|css|sc|jsx|emotion|chakra|styled|webpack|svelte)[-_]/i;
  const isStableClass = (cls) =>
    cls.length > 0 &&
    cls.length <= 40 &&
    !UNSTABLE_CLASS_RE.test(cls) &&
    !/^[a-z]*-?[0-9a-f]{6,}$/i.test(cls);

  const stableClasses = (el) =>
    Array.from(el.classList || []).filter(isStableClass);

  const queryAll = (sel) => {
    try {
      return Array.from(document.querySelectorAll(sel));
    } catch (err) {
      return null; // invalid selector
    }
  };

  // One path segment for an element. Prefers a document-unique id, then
  // tag.class when that combination is unique among same-parent siblings,
  // then structural tag:nth-of-type(k).
  function segmentFor(el) {
    const tag = el.tagName.toLowerCase();
    if (el.id && el.id.length <= 60) {
      const idSel = `#${cssEscape(el.id)}`;
      if (queryAll(idSel)?.length === 1 && document.querySelector(idSel) === el) {
        return { sel: idSel, anchored: true };
      }
    }
    const parent = el.parentElement;
    const siblings = parent ? Array.from(parent.children) : [el];
    for (const cls of stableClasses(el)) {
      const sel = `${tag}.${cssEscape(cls)}`;
      if (parent && siblings.filter((c) => c.matches(sel)).length === 1) {
        return { sel, anchored: false };
      }
    }
    const sameTag = siblings.filter((c) => c.tagName === el.tagName);
    if (sameTag.length > 1) {
      return { sel: `${tag}:nth-of-type(${sameTag.indexOf(el) + 1})`, anchored: false };
    }
    return { sel: tag, anchored: false };
  }

  // Robust unique selector for one element: structural walk to <body> (or the
  // nearest unique id), then trimmed to the shortest suffix that still
  // resolves to exactly this element. Implicit table sections (tbody/thead/
  // tfoot) that the browser inserts are skipped: the server re-parses raw
  // HTML without them, so a selector crossing one would not match there.
  const IMPLICIT_TABLE_TAGS = new Set(['tbody', 'thead', 'tfoot']);

  function uniqueSelectorFor(el) {
    if (el === document.body) return 'body';
    if (el === document.documentElement) return 'html';
    // A tbody/thead/tfoot handed in directly is resolved to its table.
    if (IMPLICIT_TABLE_TAGS.has(el.tagName.toLowerCase()) && el.parentElement?.tagName === 'TABLE') {
      el = el.parentElement;
    }
    const segments = [];
    let node = el;
    let anchored = false;
    while (node && node !== document.body && !anchored) {
      const tag = node.tagName.toLowerCase();
      if (IMPLICIT_TABLE_TAGS.has(tag) && node.parentElement?.tagName === 'TABLE') {
        node = node.parentElement;
        continue;
      }
      const seg = segmentFor(node);
      segments.unshift(seg.sel);
      anchored = seg.anchored;
      node = node.parentElement;
    }
    // Trim to the shortest suffix that still resolves to exactly this
    // element (drops ancestor context the page does not need).
    for (let i = segments.length - 1; i >= 1; i--) {
      const cand = segments.slice(i).join(' > ');
      if (queryAll(cand)?.length === 1 && document.querySelector(cand) === el) {
        return cand;
      }
    }
    return segments.join(' > ');
  }

  // Leaf-ish tags: when the user clicks one of these, the intended "item" is
  // almost always a repeated ancestor (list row, card, cell row).
  const LEAF_TAGS = new Set([
    'a', 'span', 'b', 'strong', 'em', 'i', 'u', 'small', 'code', 'time',
    'img', 'td', 'th', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'label',
    'button', 'svg'
  ]);

  function sameTagSiblings(el) {
    const parent = el.parentElement;
    if (!parent) return [];
    return Array.from(parent.children).filter((c) => c.tagName === el.tagName);
  }

  // Children used for "most common direct-child tag", looking through a sole
  // implicit tbody/thead/tfoot wrapper the browser may have inserted.
  function effectiveChildren(el) {
    const kids = Array.from(el.children);
    if (
      kids.length === 1 &&
      IMPLICIT_TABLE_TAGS.has(kids[0].tagName.toLowerCase()) &&
      el.tagName === 'TABLE'
    ) {
      return Array.from(kids[0].children);
    }
    return kids;
  }

  // Final feed selector: prefer the child combinator, but fall back to a
  // descendant combinator when the browser-only tbody wrapper sits between
  // the region and the items (the server DOM has no such wrapper, and the
  // descendant form matches in both).
  function buildItemSelector(regionSel, itemSel) {
    if (!itemSel) return regionSel;
    const child = `${regionSel} > ${itemSel}`;
    if ((queryAll(child)?.length || 0) > 0) return child;
    const descendant = `${regionSel} ${itemSel}`;
    if ((queryAll(descendant)?.length || 0) > 0) return descendant;
    return child;
  }

  // Decide the feed item selector from what the user clicked.
  //
  // Item mode: the click landed in (or on) a repeated element - climb from
  // the target to the nearest ancestor with >= 3 same-tag siblings and use
  // that sibling group as the items (adding a class only when every sibling
  // in the group shares it).
  //
  // Container mode: the click landed on a wrapper - items are the most
  // common direct-child tag inside it.
  function computeItemSelection(target) {
    let node = target;
    for (let depth = 0; depth < 8 && node && node !== document.body; depth++) {
      const group = sameTagSiblings(node);
      if (group.length >= 3) {
        const tag = node.tagName.toLowerCase();
        const shared = stableClasses(node).find((cls) =>
          group.every((sib) => sib.classList.contains(cls))
        );
        const itemSel = shared ? `${tag}.${cssEscape(shared)}` : tag;
        return {
          itemSel,
          region: node.parentElement || node,
          basis: 'repeated siblings'
        };
      }
      if (!LEAF_TAGS.has(node.tagName.toLowerCase())) break;
      node = node.parentElement;
    }

    // Container mode: most common direct-child tag.
    const counts = new Map();
    effectiveChildren(target).forEach((child) => {
      const tag = child.tagName.toLowerCase();
      counts.set(tag, (counts.get(tag) || 0) + 1);
    });
    let bestTag = null;
    let bestCount = 0;
    counts.forEach((count, tag) => {
      if (count > bestCount) {
        bestCount = count;
        bestTag = tag;
      }
    });
    if (bestTag) {
      return { itemSel: bestTag, region: target, basis: 'common child tag' };
    }
    return { itemSel: null, region: target, basis: 'single element' };
  }

  // ---------- DOM plumbing ----------
  // All picker UI lives inside a shadow root so page CSS cannot leak in and
  // picker CSS cannot leak out. The host is pointer-events:none; the bar
  // re-enables pointer events for itself.

  let root = null;
  let shadow = null;
  let hoverBox = null;
  let selBox = null;
  let matchLayer = null;
  let barEl = null;

  function ensureRoot() {
    if (root && document.getElementById(ROOT_ID)) return;
    root = document.createElement('div');
    root.id = ROOT_ID;
    root.style.cssText = `position:fixed;inset:0;pointer-events:none;z-index:${Z_TOP};`;
    shadow = root.attachShadow({ mode: 'open' });

    const style = document.createElement('style');
    style.textContent = `
:host { all: initial; }
.layer {
  position: fixed;
  pointer-events: none;
  display: none;
  border-radius: 2px;
}
.hover { border: 2px solid #ff6b00; background: rgba(255, 107, 0, 0.12); transition: all 60ms linear; }
.selected { border: 2px solid #2196F3; background: rgba(33, 150, 243, 0.08); }
.match { border: 1px solid rgba(76, 175, 80, 0.9); background: rgba(76, 175, 80, 0.10); }
.hint {
  position: fixed;
  top: 12px;
  left: 50%;
  transform: translateX(-50%);
  background: #1e1e24;
  color: #fff;
  border: 1px solid rgba(255, 255, 255, 0.18);
  border-radius: 8px;
  padding: 8px 14px;
  font-size: 13px;
  box-shadow: 0 6px 20px rgba(0, 0, 0, 0.35);
  white-space: nowrap;
}
.bar {
  position: fixed;
  left: 50%;
  bottom: 16px;
  transform: translateX(-50%);
  width: min(680px, calc(100vw - 32px));
  background: #1e1e24;
  color: #fff;
  border: 1px solid rgba(255, 255, 255, 0.16);
  border-radius: 12px;
  padding: 14px 16px;
  pointer-events: auto;
  box-shadow: 0 12px 40px rgba(0, 0, 0, 0.45);
  font-size: 13px;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
}
.bar .head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 10px;
  font-weight: 600;
  font-size: 14px;
}
.bar .row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 8px;
}
.bar label {
  color: rgba(255, 255, 255, 0.65);
  min-width: 56px;
  font-size: 12px;
}
.bar input {
  flex: 1;
  background: rgba(255, 255, 255, 0.08);
  border: 1px solid rgba(255, 255, 255, 0.18);
  color: #fff;
  border-radius: 6px;
  padding: 7px 10px;
  font-size: 13px;
  outline: none;
  min-width: 0;
}
.bar input:focus { border-color: #ff6b00; }
.bar input.selector { font-family: 'SF Mono', Menlo, Consolas, monospace; }
.bar .count {
  flex: none;
  font-size: 12px;
  padding: 5px 10px;
  border-radius: 999px;
  background: rgba(76, 175, 80, 0.18);
  color: #7bd88f;
  border: 1px solid rgba(76, 175, 80, 0.45);
  white-space: nowrap;
}
.bar .count.zero {
  background: rgba(244, 67, 54, 0.15);
  color: #ff8a80;
  border-color: rgba(244, 67, 54, 0.5);
}
.bar .count.invalid {
  background: rgba(255, 152, 0, 0.15);
  color: #ffcc80;
  border-color: rgba(255, 152, 0, 0.5);
}
.bar button {
  border: none;
  border-radius: 6px;
  padding: 8px 16px;
  font-size: 13px;
  cursor: pointer;
  font-weight: 600;
}
.bar button.subscribe { background: #ff6b00; color: #fff; }
.bar button.subscribe:disabled {
  background: rgba(255, 255, 255, 0.15);
  color: rgba(255, 255, 255, 0.45);
  cursor: not-allowed;
}
.bar button.cancel { background: rgba(255, 255, 255, 0.10); color: rgba(255, 255, 255, 0.85); }
.bar .status {
  margin-top: 8px;
  font-size: 12.5px;
  line-height: 1.45;
  display: none;
}
.bar .status.err { display: block; color: #ff8a80; }
.bar .status.ok { display: block; color: #7bd88f; }
.bar .status.busy { display: block; color: rgba(255, 255, 255, 0.65); }
    `;
    shadow.appendChild(style);

    hoverBox = document.createElement('div');
    hoverBox.className = 'layer hover';
    selBox = document.createElement('div');
    selBox.className = 'layer selected';
    matchLayer = document.createElement('div');
    shadow.appendChild(hoverBox);
    shadow.appendChild(selBox);
    shadow.appendChild(matchLayer);
    document.documentElement.appendChild(root);
  }

  function removeRoot() {
    document.getElementById(ROOT_ID)?.remove();
    root = shadow = hoverBox = selBox = matchLayer = barEl = null;
  }

  const rectToBox = (el, box) => {
    if (!el || !box) return;
    const r = el.getBoundingClientRect();
    box.style.display = 'block';
    box.style.top = `${r.top}px`;
    box.style.left = `${r.left}px`;
    box.style.width = `${r.width}px`;
    box.style.height = `${r.height}px`;
  };

  const hideBox = (box) => { if (box) box.style.display = 'none'; };

  function drawMatches(selector) {
    if (!matchLayer) return;
    matchLayer.textContent = '';
    const matches = queryAll(selector);
    if (!matches || matches.length === 0) return;
    matches.slice(0, 80).forEach((el) => {
      const box = document.createElement('div');
      box.className = 'layer match';
      matchLayer.appendChild(box);
      rectToBox(el, box);
    });
  }

  const redrawBoxes = () => {
    if (state === 'picking' && hovered) rectToBox(hovered, hoverBox);
    if ((state === 'confirm' || state === 'busy') && selected) rectToBox(selected, selBox);
    if (state === 'confirm' || state === 'busy') {
      const sel = barEl?.querySelector('input.selector')?.value;
      if (sel) drawMatches(sel);
    }
  };

  // ---------- pick mode ----------

  // Events retarget to the shadow host, so own-UI detection is a host check.
  const isOwnUi = (el) => !!(el && (el === root || el.closest?.(`#${ROOT_ID}`)));

  function onPickMove(e) {
    if (state !== 'picking') return;
    const target = e.target;
    if (isOwnUi(target) || !target || target === document.documentElement) {
      hovered = null;
      hideBox(hoverBox);
      return;
    }
    hovered = target;
    rectToBox(target, hoverBox);
  }

  function onPickClick(e) {
    if (state !== 'picking') return;
    e.preventDefault();
    e.stopPropagation();
    const target = e.target;
    if (isOwnUi(target) || !target || target === document.documentElement || target === document.body) {
      return;
    }
    selectElement(target);
  }

  function onKeyDown(e) {
    if (e.key !== 'Escape') return;
    if (state === 'picking' || state === 'confirm' || state === 'busy') {
      e.preventDefault();
      e.stopPropagation();
      cancel();
    }
  }

  function onScroll() {
    if (state === 'off' || !root) return;
    redrawBoxes();
  }

  function startPickMode() {
    ensureRoot();
    clearTimeout(teardownTimer);
    state = 'picking';
    hovered = null;
    selected = null;
    serverAvailable = null;
    document.documentElement.style.setProperty('cursor', 'crosshair', 'important');
    shadow.querySelector('.hint')?.remove();
    const hint = document.createElement('div');
    hint.className = 'hint';
    hint.textContent = 'Click the region that lists the feed items. Esc cancels.';
    shadow.appendChild(hint);
    hideBox(hoverBox);
    hideBox(selBox);
    matchLayer.textContent = '';
    if (barEl) barEl.style.display = 'none';
  }

  function cancel() {
    state = 'off';
    document.documentElement.style.removeProperty('cursor');
    removeRoot();
  }

  // ---------- confirm bar ----------

  function selectElement(target) {
    state = 'confirm';
    selected = target;
    document.documentElement.style.removeProperty('cursor');
    shadow.querySelector('.hint')?.remove();
    hideBox(hoverBox);

    const { itemSel, region, basis } = computeItemSelection(target);
    const regionSel = uniqueSelectorFor(region);
    let feedSelector = buildItemSelector(regionSel, itemSel);
    if (feedSelector.length > 500) feedSelector = feedSelector.slice(0, 500);

    buildBar(feedSelector, basis);
    rectToBox(selected, selBox);
    updateCount();
    drawMatches(feedSelector);
    checkServer();
    barEl.querySelector('input.selector')?.focus();
  }

  function buildBar(feedSelector, basis) {
    if (barEl) barEl.remove();
    barEl = document.createElement('div');
    barEl.className = 'bar';
    barEl.innerHTML = `
      <div class="head">
        <span>Generate feed from this page</span>
        <button type="button" class="cancel">Cancel</button>
      </div>
      <div class="row">
        <label for="omi-pk-selector">Selector</label>
        <input type="text" class="selector" id="omi-pk-selector"
               spellcheck="false" autocomplete="off">
        <span class="count"></span>
      </div>
      <div class="row">
        <label for="omi-pk-title">Title</label>
        <input type="text" class="title" id="omi-pk-title"
               spellcheck="false" autocomplete="off">
        <button type="button" class="subscribe">Subscribe</button>
      </div>
      <div class="status" role="status"></div>
    `;
    shadow.appendChild(barEl);

    const selectorInput = barEl.querySelector('input.selector');
    const titleInput = barEl.querySelector('input.title');
    selectorInput.value = feedSelector;
    titleInput.value = (document.title || '').trim().slice(0, 200);
    selectorInput.title = `Detected via ${basis}`;

    barEl.addEventListener('click', (e) => e.stopPropagation());
    barEl.addEventListener('keyup', (e) => e.stopPropagation());
    barEl.addEventListener('keydown', (e) => {
      e.stopPropagation();
      if (e.key === 'Enter') {
        e.preventDefault();
        submit();
      }
    });
    barEl.querySelector('button.cancel').addEventListener('click', cancel);
    barEl.querySelector('button.subscribe').addEventListener('click', submit);
    selectorInput.addEventListener('input', () => {
      clearTimeout(matchTimer);
      matchTimer = setTimeout(() => {
        updateCount();
        drawMatches(selectorInput.value.trim());
      }, 150);
    });
  }

  function setStatus(text, kind) {
    const status = barEl?.querySelector('.status');
    if (!status) return;
    status.textContent = text;
    status.className = `status ${kind || ''}`.trim();
  }

  function updateCount() {
    const countEl = barEl?.querySelector('.count');
    const selectorInput = barEl?.querySelector('input.selector');
    if (!countEl || !selectorInput) return;
    const value = selectorInput.value.trim();
    if (!value) {
      countEl.textContent = 'Empty selector';
      countEl.className = 'count invalid';
      return;
    }
    const matches = queryAll(value);
    if (matches === null) {
      countEl.textContent = 'Invalid selector';
      countEl.className = 'count invalid';
      return;
    }
    countEl.textContent = `${matches.length} item${matches.length === 1 ? '' : 's'}`;
    countEl.className = matches.length === 0 ? 'count zero' : 'count';
  }

  async function checkServer() {
    const subscribeBtn = barEl?.querySelector('button.subscribe');
    try {
      const response = await chrome.runtime.sendMessage({ action: 'page-picker-context' });
      serverAvailable = !!(response && response.serverAvailable);
    } catch (err) {
      serverAvailable = false;
    }
    if (state !== 'confirm' || !barEl) return;
    if (!serverAvailable) {
      setStatus('Page feeds require a server connection. Sign in to a server to monitor pages.', 'err');
      if (subscribeBtn) subscribeBtn.disabled = true;
    } else {
      setStatus('');
      if (subscribeBtn) subscribeBtn.disabled = false;
    }
  }

  async function submit() {
    if (state !== 'confirm') return;
    const selectorInput = barEl.querySelector('input.selector');
    const titleInput = barEl.querySelector('input.title');
    const subscribeBtn = barEl.querySelector('button.subscribe');
    const selector = selectorInput.value.trim();
    if (!selector) {
      setStatus('Selector is empty.', 'err');
      return;
    }
    if (selector.length > 500) {
      setStatus('Selector is longer than 500 characters.', 'err');
      return;
    }
    if (serverAvailable === false) {
      setStatus('Page feeds require a server connection. Sign in to a server to monitor pages.', 'err');
      return;
    }

    state = 'busy';
    subscribeBtn.disabled = true;
    setStatus('Subscribing...', 'busy');

    let response = null;
    try {
      response = await chrome.runtime.sendMessage({
        action: 'subscribe-page-feed',
        data: {
          pageUrl: window.location.href,
          pageSelector: selector,
          title: titleInput.value.trim() || undefined
        }
      });
    } catch (err) {
      response = { error: err.message };
    }

    if (state !== 'busy') return; // cancelled mid-flight

    if (response && response.success) {
      const count = queryAll(selector)?.length ?? 0;
      setStatus(`Subscribed. Page feed "${response.feed?.title || titleInput.value.trim()}" created with ${count} detected item${count === 1 ? '' : 's'}. New items appear after the next refresh.`, 'ok');
      teardownTimer = setTimeout(cancel, 2800);
      return;
    }

    state = 'confirm';
    subscribeBtn.disabled = serverAvailable === false;
    if (response && response.error === 'noserver') {
      setStatus('Page feeds require a server connection. Sign in to a server to monitor pages.', 'err');
    } else {
      setStatus((response && response.error) || 'Subscribe failed.', 'err');
    }
  }

  // ---------- wiring ----------

  document.addEventListener('mousemove', onPickMove, true);
  document.addEventListener('click', onPickClick, true);
  document.addEventListener('keydown', onKeyDown, true);
  window.addEventListener('scroll', onScroll, { passive: true, capture: true });
  window.addEventListener('resize', onScroll, { passive: true, capture: true });

  window.__omiPagePickerStart = startPickMode;
  startPickMode();
})();
