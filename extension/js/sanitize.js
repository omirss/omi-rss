// Client-side HTML sanitizer - defense-in-depth allowlist walker.
// The server sanitizes content already; this guards the UI sinks against
// hostile or misconfigured servers. No innerHTML of raw strings: parse into
// a detached <template>, then rebuild the tree keeping only allowed
// tags/attributes. Loaded by popup.html and sidepanel.html before use.
(function (global) {
  const ALLOWED_TAGS = new Set([
    'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'a', 'b',
    'i', 'em', 'strong', 'blockquote', 'code', 'pre', 'br', 'hr', 'img',
    'time', 'figure', 'figcaption'
  ]);
  const ALLOWED_ATTRS = new Set(['href', 'src', 'alt', 'title']);
  const URL_ATTRS = new Set(['href', 'src']);
  // Elements whose content must be dropped entirely, not unwrapped.
  const DROP_CONTENT_TAGS = new Set(['script', 'style', 'iframe', 'object', 'embed', 'noscript', 'template']);

  function isSafeUrl(value) {
    try {
      const url = new URL(String(value), 'http://omi.invalid');
      return url.protocol === 'http:' || url.protocol === 'https:';
    } catch (err) {
      return false;
    }
  }

  function sanitizeChildren(srcNode, dstNode) {
    for (const child of Array.from(srcNode.childNodes)) {
      if (child.nodeType === Node.TEXT_NODE) {
        dstNode.appendChild(document.createTextNode(child.textContent));
        continue;
      }
      if (child.nodeType !== Node.ELEMENT_NODE) continue;
      const tag = child.tagName.toLowerCase();
      if (DROP_CONTENT_TAGS.has(tag)) continue;
      if (!ALLOWED_TAGS.has(tag)) {
        sanitizeChildren(child, dstNode); // unwrap: keep sanitized children
        continue;
      }
      const el = document.createElement(tag);
      for (const attr of Array.from(child.attributes)) {
        const name = attr.name.toLowerCase();
        if (!ALLOWED_ATTRS.has(name)) continue;
        if (URL_ATTRS.has(name) && !isSafeUrl(attr.value)) continue;
        el.setAttribute(name, attr.value);
      }
      dstNode.appendChild(el);
      sanitizeChildren(child, el);
    }
  }

  // Returns a DocumentFragment built from only the allowed parts of `html`.
  function sanitizeHtml(html) {
    const template = document.createElement('template');
    template.innerHTML = String(html == null ? '' : html);
    const fragment = document.createDocumentFragment();
    sanitizeChildren(template.content, fragment);
    return fragment;
  }

  // Replace `container` content with the sanitized `html`.
  function renderSanitized(container, html) {
    container.textContent = '';
    container.appendChild(sanitizeHtml(html));
  }

  global.OmiSanitize = { sanitizeHtml, renderSanitized, isSafeUrl };
})(typeof window !== 'undefined' ? window : globalThis);
