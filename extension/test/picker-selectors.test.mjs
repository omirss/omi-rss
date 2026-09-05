// Tests for extension/js/picker-selectors.js - plain `node --test`, no deps.
// A minimal DOM shim provides exactly what the selector helpers use:
// tagName/id/classList/parentElement/children/matches plus
// document.querySelector(All) over a constrained selector grammar
// (tag, #id, .class, tag:nth-of-type(n), child ' > ' and descendant ' ').
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const {
  cssEscape, uniqueSelectorFor, buildItemSelector, computeItemSelection
} = require('../js/picker-selectors.js');

// ---------- tiny DOM shim ----------

class ClassList {
  constructor(classes = []) { this._set = new Set(classes); }
  contains(c) { return this._set.has(c); }
  *[Symbol.iterator]() { yield* this._set; }
}

class El {
  constructor(tagName, opts = {}) {
    const { id = '', classes = [] } = opts || {};
    this.tagName = tagName.toUpperCase();
    this.id = id;
    this.classList = new ClassList(classes);
    this.parent = null;
    this.kids = [];
  }
  get parentElement() { return this.parent; }
  get children() { return this.kids; }
  matches(sel) { return matchChain(this, parseSelector(sel)); }
}

const parseCompound = (compound) => {
  const m = /^(?:(\*)|([a-zA-Z][a-zA-Z0-9-]*))?(?:#([^\s.:#]+))?((?:\.[^\s.:#]+)*)?(?::nth-of-type\((\d+)\))?$/.exec(compound);
  if (!m) throw new Error(`shim: unsupported compound "${compound}"`);
  return {
    tag: m[2] || null,
    id: m[3] || null,
    classes: m[4] ? m[4].slice(1).split('.') : [],
    nth: m[5] ? Number(m[5]) : null
  };
};

const parseSelector = (sel) => {
  const parts = sel.split(/\s+/).filter(Boolean);
  const compounds = [];
  const combinators = [];
  for (const part of parts) {
    if (part === '>') combinators.push('>');
    else compounds.push(parseCompound(part));
  }
  return { compounds, combinators };
};

const matchCompound = (el, c) => {
  if (c.tag && el.tagName.toLowerCase() !== c.tag) return false;
  if (c.id && el.id !== c.id) return false;
  if (c.classes.some((cls) => !el.classList.contains(cls))) return false;
  if (c.nth !== null) {
    if (!el.parent) return false;
    const sameTag = el.parent.kids.filter((k) => k.tagName === el.tagName);
    if (sameTag.indexOf(el) + 1 !== c.nth) return false;
  }
  return true;
};

const matchChain = (el, { compounds, combinators }) => {
  if (!compounds.length || !matchCompound(el, compounds[compounds.length - 1])) return false;
  if (compounds.length === 1) return true;
  const [head, ...rest] = combinators; // rest aligned to remaining compounds
  const sub = { compounds: compounds.slice(0, -1), combinators: combinators.slice(0, -1) };
  const comb = combinators[combinators.length - 1];
  if (comb === '>') {
    return el.parent !== null && matchChain(el.parent, sub);
  }
  let anc = el.parent;
  while (anc) {
    if (matchChain(anc, sub)) return true;
    anc = anc.parent;
  }
  return false;
};

const collect = (el, out) => {
  out.push(el);
  el.kids.forEach((k) => collect(k, out));
};

const buildDoc = (...bodyKids) => {
  const html = new El('html');
  const body = new El('body');
  html.kids.push(body);
  body.parent = html;
  const add = (parent, kid) => { kid.parent = parent; parent.kids.push(kid); return kid; };
  bodyKids.forEach((k) => add(body, k));
  const all = () => { const out = []; collect(html, out); return out; };
  globalThis.document = {
    documentElement: html,
    body,
    querySelectorAll(sel) {
      const parsed = parseSelector(sel);
      return all().filter((el) => matchChain(el, parsed));
    },
    querySelector(sel) {
      const parsed = parseSelector(sel);
      return all().find((el) => matchChain(el, parsed)) || null;
    }
  };
  return { body, add };
};

const el = (tag, opts, ...kids) => {
  const node = new El(tag, opts);
  kids.forEach((k) => { k.parent = node; node.kids.push(k); });
  return node;
};

// picker flow (page-picker.js selectElement) for composition tests
const feedSelectorFor = (target) => {
  const { itemSel, region } = computeItemSelection(target);
  return buildItemSelector(uniqueSelectorFor(region), itemSel);
};

// ---------- tests ----------

test('id path: document-unique id becomes the whole selector', () => {
  const link = el('a');
  const posts = el('div', { id: 'posts' }, link);
  buildDoc(posts);
  assert.equal(uniqueSelectorFor(posts), '#posts');
  // the child may trim to the shortest unique suffix; the contract is that
  // the selector resolves to exactly this element
  const linkSel = uniqueSelectorFor(link);
  assert.equal(document.querySelector(linkSel), link);
  assert.ok(linkSel === 'a' || linkSel === '#posts > a');
});

test('nth-of-type path: repeated same-tag siblings get structural index', () => {
  const content = el('div', { classes: ['content'] },
    el('h1'),
    el('p'), el('p'), el('p')
  );
  buildDoc(content);
  const third = content.kids[3];
  assert.equal(uniqueSelectorFor(third), 'p:nth-of-type(3)');
});

test('implicit-t tbody path: table.post-list tr case (descendant fallback)', () => {
  // What the browser builds from <table class="post-list"><tr>...: a tbody
  // the server DOM will not have.
  const trs = [el('tr'), el('tr'), el('tr')];
  const tbody = el('tbody', null, ...trs);
  const table = el('table', { classes: ['post-list'] }, tbody);
  buildDoc(table);

  // uniqueSelectorFor collapses an implicit tbody to its table
  assert.equal(uniqueSelectorFor(tbody), 'table.post-list');

  // full picker flow on the first row: 'table.post-list > tr' cannot match
  // through the browser-inserted tbody, so the descendant form wins
  assert.equal(feedSelectorFor(trs[0]), 'table.post-list tr');
  assert.equal(document.querySelectorAll('table.post-list tr').length, 3);
  assert.equal(document.querySelectorAll('table.post-list > tr').length, 0);
});

test('buildItemSelector falls back to descendant when child matches nothing', () => {
  const spans = [el('span', { classes: ['item'] }), el('span', { classes: ['item'] })];
  const mid = el('div', { classes: ['mid'] }, ...spans);
  const wrap = el('div', { id: 'wrap' }, mid);
  buildDoc(wrap);
  assert.equal(buildItemSelector('#wrap', 'span'), '#wrap span');
  assert.equal(buildItemSelector('#wrap', 'div'), '#wrap > div');
});

test('computeItemSelection item mode adds a class shared by the whole group', () => {
  const cards = [1, 2, 3].map(() => el('div', { classes: ['card'] }));
  const list = el('div', { classes: ['list'] }, ...cards);
  buildDoc(list);
  const result = computeItemSelection(cards[0].kids ? cards[0] : cards[0]);
  assert.equal(result.itemSel, 'div.card');
  assert.equal(result.region, list);
  assert.equal(result.basis, 'repeated siblings');
});

test('computeItemSelection container mode uses the most common child tag', () => {
  const region = el('div', { id: 'region' },
    el('a'), el('a'), el('a'), el('span')
  );
  buildDoc(region);
  const result = computeItemSelection(region);
  assert.equal(result.itemSel, 'a');
  assert.equal(result.basis, 'common child tag');
  assert.equal(feedSelectorFor(region), '#region > a');
});

test('cssEscape: fallback path escapes every unsafe character', () => {
  assert.equal(cssEscape('plain'), 'plain');
  assert.equal(cssEscape('a b'), 'a\\ b');
  assert.equal(cssEscape('x.y:z'), 'x\\.y\\:z');
  assert.equal(cssEscape(''), '');
  // escaped output must contain no bare specials (digits/word chars stay bare)
  assert.match(cssEscape('we.id: 1'), /^we\\.id\\:\\ 1$/);
});
