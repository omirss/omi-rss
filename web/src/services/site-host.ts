// Host-affinity rule for bring-your-own-subscription headers: stored
// credentials (Cookie, Authorization) may only ride requests whose origin
// is EXACTLY the origin they were configured for. Shared by the
// article-extraction header gate (worker) and both redirect-drop gates
// (feed fetch, document fetch).
//
// Exact origin (scheme + host + port) is the only safe default without
// shipping a public-suffix list: last-two-label "site" matching lets
// unrelated tenants share a suffix (victim.co.uk ~ attacker.co.uk), and
// ignoring ports/scheme would forward credentials across hosts that
// merely resolve to the same name or downgrade https → http. Subdomain
// redirects therefore drop credentials — the redirect target is chosen
// by the feed host, not the subscriber.

function httpOriginOf(url: string): string | null {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return null;
    if (parsed.username || parsed.password) return null;
    return parsed.origin;
  } catch {
    return null;
  }
}

export function sameSiteHost(aUrl: string, bUrl: string): boolean {
  const a = httpOriginOf(aUrl);
  const b = httpOriginOf(bUrl);
  return a !== null && a === b;
}
