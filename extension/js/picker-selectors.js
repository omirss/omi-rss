// Pure DOM selector helpers for the page-feed picker.
// Extracted from page-picker.js so they are testable with plain node --test
// (see extension/test/picker-selectors.test.mjs). No chrome.* APIs here:
// everything operates on the global `document` at call time.
//
// Loaded as a classic script (chrome.scripting.executeScript files list)
// right before page-picker.js; also require()-able from Node tests.
(function (global) {
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

  const api = {
    cssEscape,
    isStableClass,
    stableClasses,
    segmentFor,
    uniqueSelectorFor,
    sameTagSiblings,
    effectiveChildren,
    buildItemSelector,
    computeItemSelection,
    LEAF_TAGS,
    IMPLICIT_TABLE_TAGS
  };

  global.OmiPickerSelectors = api;
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
  }
})(typeof window !== 'undefined' ? window : globalThis);
