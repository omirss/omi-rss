// Favicons are derived from the feed's own origin — the browser resolves
// them, no third-party favicon service involved.
export function faviconUrlFor(siteUrl: string | null | undefined): string | null {
  if (!siteUrl) return null;
  try {
    return `${new URL(siteUrl).origin}/favicon.ico`;
  } catch {
    return null;
  }
}
