// On-demand page-feed picker for Omi RSS.
// Injected via chrome.scripting.executeScript from the background when the
// user activates "Generate feed from this page" (popup button or context
// menu). Runs in the content-script isolated world. Not listed in
// manifest content_scripts: it loads only when needed. The pure selector
// helpers live in js/picker-selectors.js, injected right before this file.
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

  const {
    uniqueSelectorFor, buildItemSelector, computeItemSelection
  } = window.OmiPickerSelectors;

  const ROOT_ID = 'omi-page-picker-root';
  const Z_TOP = 2147483600;
  const PICK_HINT = 'Click the region that lists the feed items. Esc cancels.';
  const SHADOW_HINT = 'This page renders inside shadow DOM - picking is not supported here';

  // 'off' | 'picking' | 'confirm' | 'busy'
  let state = 'off';
  let hovered = null;
  let selected = null;
  let serverAvailable = null;
  let matchTimer = null;
  let teardownTimer = null;
  let scrollRaf = null;

  const queryAll = (sel) => {
    try {
      return Array.from(document.querySelectorAll(sel));
    } catch (err) {
      return null; // invalid selector
    }
  };

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

  // True when the event was retargeted through a shadow boundary: the
  // composed path crosses a ShadowRoot before reaching the document. The
  // visible target is then only the host element, and a selector built from
  // it (e.g. "#app-root") would never match the real items - refuse honestly.
  const crossesShadowBoundary = (e) => {
    for (const node of e.composedPath()) {
      if (node instanceof Document) return false;
      if (node instanceof ShadowRoot) return true;
    }
    return false;
  };

  function setHint(text) {
    const hint = shadow.querySelector('.hint');
    if (hint) hint.textContent = text;
  }

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
    setHint(PICK_HINT);
  }

  function onPickClick(e) {
    if (state !== 'picking') return;
    e.preventDefault();
    e.stopPropagation();
    const target = e.target;
    if (isOwnUi(target) || !target || target === document.documentElement || target === document.body) {
      return;
    }
    if (crossesShadowBoundary(e)) {
      // Stay in pick mode: light-DOM regions on the same page are still
      // pickable; just tell the truth about the shadow-rendered area.
      setHint(SHADOW_HINT);
      return;
    }
    selectElement(target);
  }

  function onKeyDown(e) {
    if (e.key !== 'Escape') return;
    // Esc while editing the selector/title inputs just blurs the input;
    // a second Esc (focus elsewhere) cancels the picker.
    if (state === 'confirm' && barEl) {
      const path = e.composedPath();
      const first = path[0];
      if (first && first.tagName === 'INPUT' && path.includes(barEl)) {
        e.preventDefault();
        e.stopPropagation();
        first.blur();
        return;
      }
    }
    if (state === 'picking' || state === 'confirm' || state === 'busy') {
      e.preventDefault();
      e.stopPropagation();
      cancel();
    }
  }

  function onScroll() {
    if (state === 'off' || !root) return;
    // Coalesce scroll/resize repaints to one per frame: redrawBoxes calls
    // drawMatches, which re-queries the document for every matched item.
    if (scrollRaf) return;
    scrollRaf = requestAnimationFrame(() => {
      scrollRaf = null;
      if (state === 'off' || !root) return;
      redrawBoxes();
    });
  }

  function startPickMode() {
    ensureRoot();
    clearTimeout(teardownTimer);
    cancelScrollRaf();
    state = 'picking';
    hovered = null;
    selected = null;
    serverAvailable = null;
    document.documentElement.style.setProperty('cursor', 'crosshair', 'important');
    shadow.querySelector('.hint')?.remove();
    const hint = document.createElement('div');
    hint.className = 'hint';
    hint.textContent = PICK_HINT;
    shadow.appendChild(hint);
    hideBox(hoverBox);
    hideBox(selBox);
    matchLayer.textContent = '';
    if (barEl) barEl.style.display = 'none';
  }

  function cancelScrollRaf() {
    if (scrollRaf) {
      cancelAnimationFrame(scrollRaf);
      scrollRaf = null;
    }
  }

  function cancel() {
    state = 'off';
    cancelScrollRaf();
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
