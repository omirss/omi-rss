export function formatAbsoluteDate(iso: string | null | undefined): string {
  if (!iso) return "Unknown date";
  const time = Date.parse(iso);
  if (Number.isNaN(time)) return "Unknown date";
  try {
    return new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short", year: "numeric" }).format(new Date(time));
  } catch {
    return iso.slice(0, 10);
  }
}

export function formatRelativeTime(iso: string | null | undefined): string {
  if (!iso) return "Unknown date";
  const time = Date.parse(iso);
  if (Number.isNaN(time)) return "Unknown date";
  const diffMs = Date.now() - time;
  const minutes = Math.floor(diffMs / 60000);
  if (minutes < 1) return "Just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  return formatAbsoluteDate(iso);
}

export function htmlToPlainText(html: string | null | undefined): string {
  if (!html) return "";
  return html
    .replace(/<[^>]*>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim();
}

export function estimateReadMinutes(html: string | null | undefined): number {
  const words = htmlToPlainText(html).split(" ").filter(Boolean).length;
  if (words === 0) return 0;
  return Math.max(1, Math.round(words / 220));
}

export function normalizeFeedUrl(url: string): string {
  let value = url.trim().toLowerCase();
  value = value.replace(/^https?:\/\//, "");
  value = value.replace(/^www\./, "");
  value = value.replace(/\/+$/, "");
  return value;
}
