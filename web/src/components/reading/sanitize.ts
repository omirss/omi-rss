import DOMPurify from "dompurify";

let hooksReady = false;

function ensureHooks(): void {
  if (hooksReady) return;
  hooksReady = true;
  DOMPurify.addHook("afterSanitizeAttributes", (node) => {
    const element = node as Element;
    if (typeof element.setAttribute !== "function") return;
    if (element.tagName === "A") {
      element.setAttribute("target", "_blank");
      element.setAttribute("rel", "noopener noreferrer");
    } else if (element.tagName === "IMG") {
      element.setAttribute("loading", "lazy");
    }
  });
}

export function sanitizeArticleHtml(html: string): string {
  if (!html) return "";
  ensureHooks();
  return DOMPurify.sanitize(html, {
    USE_PROFILES: { html: true },
    FORBID_TAGS: ["style", "form", "input", "button", "select", "textarea", "script", "iframe", "object", "embed"],
    FORBID_ATTR: ["style", "class", "id"],
  });
}
