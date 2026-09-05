// IP address utilities shared by the SSRF guard (feed-fetch) and the
// TRUSTED_PROXY rate-limit key resolution. Pure functions, no I/O.

const IPV4_V6_MAPPED = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i;

export function normalizeIp(ip: string): string {
  const trimmed = ip.trim().toLowerCase();
  const mapped = trimmed.match(IPV4_V6_MAPPED);
  return mapped ? mapped[1] : trimmed;
}

export type IpVersion = 4 | 6;

export function ipVersion(ip: string): IpVersion | null {
  const normalized = normalizeIp(ip);
  if (/^\d{1,3}(?:\.\d{1,3}){3}$/.test(normalized)) {
    return 4;
  }
  if (normalized.includes(":")) {
    return 6;
  }
  return null;
}

function ipv4ToBigInt(ip: string): bigint {
  const parts = ip.split(".").map((p) => BigInt(parseInt(p, 10)));
  return (parts[0] << 24n) | (parts[1] << 16n) | (parts[2] << 8n) | parts[3];
}

// Expands an IPv6 address (including :: compression) to its 128-bit value.
// Returns null for malformed addresses.
function ipv6ToBigInt(ip: string): bigint | null {
  let noZone = ip;
  const zoneSplit = noZone.split("%");
  if (zoneSplit.length === 2) {
    noZone = zoneSplit[0];
  }
  let head = noZone;
  let tail = "";
  const doubleColon = noZone.indexOf("::");
  if (doubleColon !== -1) {
    if (noZone.indexOf("::", doubleColon + 1) !== -1) {
      return null;
    }
    head = noZone.slice(0, doubleColon);
    tail = noZone.slice(doubleColon + 2);
  }
  const headGroups = head ? head.split(":") : [];
  const tailGroups = tail ? tail.split(":") : [];
  const embeddedV4 = [...headGroups, ...tailGroups].some((g) => g.includes("."));
  const groupCount = headGroups.length + tailGroups.length + (embeddedV4 ? 1 : 0);

  if (doubleColon === -1 && groupCount !== 8) {
    return null;
  }
  if (doubleColon !== -1 && groupCount > 7) {
    return null;
  }

  const groups: bigint[] = [];
  const parseGroup = (group: string): bigint | null => {
    if (group.includes(".")) {
      const v4 = ipv4ToBigInt(group);
      groups.push((v4 >> 16n) & 0xffffn);
      return v4 & 0xffffn;
    }
    if (!/^[0-9a-f]{1,4}$/.test(group)) {
      return null;
    }
    return BigInt(parseInt(group, 16));
  };

  for (const group of headGroups) {
    const value = parseGroup(group);
    if (value === null) {
      return null;
    }
    groups.push(value);
  }
  if (doubleColon !== -1) {
    const fill = 8 - groupCount;
    for (let i = 0; i < fill; i++) {
      groups.push(0n);
    }
  }
  for (const group of tailGroups) {
    const value = parseGroup(group);
    if (value === null) {
      return null;
    }
    groups.push(value);
  }

  let value = 0n;
  for (const group of groups) {
    value = (value << 16n) | group;
  }
  return value;
}

export function ipToBigInt(ip: string): { version: IpVersion; value: bigint } | null {
  const normalized = normalizeIp(ip);
  if (ipVersion(normalized) === 4) {
    return { version: 4, value: ipv4ToBigInt(normalized) };
  }
  const v6 = ipv6ToBigInt(normalized);
  if (v6 !== null) {
    return { version: 6, value: v6 };
  }
  return null;
}

function cidrToRange(cidr: string): { version: IpVersion; start: bigint; end: bigint } | null {
  const [network, prefixRaw] = cidr.split("/");
  if (!network) {
    return null;
  }
  const parsed = ipToBigInt(network);
  if (!parsed) {
    return null;
  }
  let prefix: number;
  if (prefixRaw === undefined) {
    prefix = parsed.version === 4 ? 32 : 128;
  } else {
    prefix = parseInt(prefixRaw, 10);
    if (!Number.isInteger(prefix) || prefix < 0 || prefix > (parsed.version === 4 ? 32 : 128)) {
      return null;
    }
  }
  const bits = parsed.version === 4 ? 32n : 128n;
  const size = 1n << (bits - BigInt(prefix));
  const mask = ((1n << bits) - 1n) & ~((size - 1n));
  return { version: parsed.version, start: parsed.value & mask, end: (parsed.value & mask) + size - 1n };
}

export function ipInCidr(ip: string, cidr: string): boolean {
  const parsed = ipToBigInt(ip);
  const range = cidrToRange(cidr);
  if (!parsed || !range || parsed.version !== range.version) {
    return false;
  }
  return parsed.value >= range.start && parsed.value <= range.end;
}

// Loopback, private, and link-local ranges blocked for outbound feed fetches.
// Covers the audit's list plus IPv4 unspecified (0.0.0.0/8, which routes to
// localhost) — kept as an explicit list so the blocked set is auditable.
const BLOCKED_CIDRS: string[] = [
  "127.0.0.0/8",
  "10.0.0.0/8",
  "172.16.0.0/12",
  "192.168.0.0/16",
  "169.254.0.0/16",
  "0.0.0.0/8",
  "::1/128",
  "fc00::/7",
  "fe80::/10",
  "::/128",
];

export function isBlockedOutboundAddress(ip: string): boolean {
  const normalized = normalizeIp(ip);
  return BLOCKED_CIDRS.some((cidr) => ipInCidr(normalized, cidr));
}
