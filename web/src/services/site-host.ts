// Host-affinity rule for bring-your-own-subscription headers: stored
// credentials (Cookie, Authorization) may only ride requests whose host is
// the same site as the URL they were configured for. Shared by the
// article-extraction header gate (worker) and both redirect-drop gates
// (feed fetch, document fetch).
//
// "Same site" is a naive registrable-domain match: the last two DNS labels
// must be equal (feeds.example.com ~ www.example.com ~ example.com).
// Multi-label public suffixes like co.uk are NOT recognized
// (a.example.co.uk ~ b.example.co.uk counts as same-site) — documented,
// accepted edge. IP literals and single-label hosts (localhost) have no
// registrable domain and must match exactly. Ports are ignored
// (URL.hostname excludes them), so 127.0.0.1:3000 ~ 127.0.0.1:9999 is
// same-host — and 127.0.0.1 vs localhost is not.

const IPV4_RE = /^\d{1,3}(\.\d{1,3}){3}$/;

function hostnameOf(url: string): string | null {
  try {
    return new URL(url).hostname.toLowerCase();
  } catch {
    return null;
  }
}

function registrableDomain(hostname: string): string | null {
  if (IPV4_RE.test(hostname) || hostname.includes(":")) return null;
  const labels = hostname.split(".");
  if (labels.length < 2) return null;
  return labels.slice(-2).join(".");
}

export function sameSiteHost(aUrl: string, bUrl: string): boolean {
  const a = hostnameOf(aUrl);
  const b = hostnameOf(bUrl);
  if (!a || !b) return false;
  if (a === b) return true;
  const domainA = registrableDomain(a);
  const domainB = registrableDomain(b);
  return domainA !== null && domainA === domainB;
}
