import { describe, it, expect } from "vitest";
import { isBlockedOutboundAddress, ipInCidr, ipVersion, normalizeIp } from "./ip.js";

// SSRF guard unit contracts (audit F1 payloads included): the blocked-set
// decision must be by address VALUE, not textual form — WHATWG URL
// canonicalizes [::ffff:127.0.0.1] to hex groups (::ffff:7f00:1), and both
// serializations of an IPv4-mapped/NAT64 address must evaluate the embedded
// IPv4 against the blocked ranges.

describe("normalizeIp / ipVersion", () => {
  it("rewrites only the dotted-quad mapped form to IPv4", () => {
    expect(normalizeIp("::ffff:127.0.0.1")).toBe("127.0.0.1");
    expect(ipVersion("::ffff:127.0.0.1")).toBe(4);
    // The hex serialization URL parsers produce stays IPv6.
    expect(normalizeIp("::ffff:7f00:1")).toBe("::ffff:7f00:1");
    expect(ipVersion("::ffff:7f00:1")).toBe(6);
  });

  it("yields hex groups for bracketed mapped literals", () => {
    expect(new URL("http://[::ffff:127.0.0.1]/").hostname).toBe("[::ffff:7f00:1]");
    expect(new URL("http://[::ffff:a9fe:a9fe]/").hostname).toBe("[::ffff:a9fe:a9fe]");
  });
});

describe("isBlockedOutboundAddress IPv4", () => {
  it("blocks loopback, private, link-local and unspecified", () => {
    for (const ip of ["127.0.0.1", "127.0.0.2", "10.1.2.3", "172.16.0.9", "192.168.1.1", "169.254.169.254", "0.0.0.0"]) {
      expect(isBlockedOutboundAddress(ip)).toBe(true);
    }
  });

  it("passes public IPv4", () => {
    expect(isBlockedOutboundAddress("8.8.8.8")).toBe(false);
    expect(isBlockedOutboundAddress("1.1.1.1")).toBe(false);
  });
});

describe("isBlockedOutboundAddress IPv6", () => {
  it("blocks loopback, ULA, link-local and unspecified", () => {
    for (const ip of ["::1", "fd00::1", "fe80::1", "::"]) {
      expect(isBlockedOutboundAddress(ip)).toBe(true);
    }
  });

  it("passes global unicast IPv6", () => {
    expect(isBlockedOutboundAddress("2606:4700::1111")).toBe(false);
    expect(isBlockedOutboundAddress("2001:db8::1")).toBe(false);
  });
});

describe("isBlockedOutboundAddress embedded IPv4 (audit F1 payloads)", () => {
  it("blocks IPv4-mapped loopback in dotted and hex serializations", () => {
    expect(isBlockedOutboundAddress("::ffff:127.0.0.1")).toBe(true);
    expect(isBlockedOutboundAddress("::ffff:7f00:1")).toBe(true);
  });

  it("blocks IPv4-mapped link-local metadata (169.254.169.254)", () => {
    expect(isBlockedOutboundAddress("::ffff:a9fe:a9fe")).toBe(true);
    expect(isBlockedOutboundAddress("::ffff:169.254.169.254")).toBe(true);
  });

  it("blocks IPv4-mapped private ranges", () => {
    expect(isBlockedOutboundAddress("::ffff:a01:203")).toBe(true); // 10.1.2.3
    expect(isBlockedOutboundAddress("::ffff:192.168.1.1")).toBe(true);
  });

  it("blocks NAT64 (64:ff9b::/96) embedded blocked IPv4", () => {
    expect(isBlockedOutboundAddress("64:ff9b::7f00:1")).toBe(true); // 127.0.0.1
    expect(isBlockedOutboundAddress("64:ff9b::a9fe:a9fe")).toBe(true); // 169.254.169.254
  });

  it("blocks the deprecated IPv4-compatible form (::/96)", () => {
    expect(isBlockedOutboundAddress("::7f00:1")).toBe(true); // 127.0.0.1
  });

  it("blocks the exact hostname new URL() produces for the audit payloads", () => {
    for (const literal of ["::ffff:127.0.0.1", "::ffff:a9fe:a9fe", "64:ff9b::7f00:1"]) {
      const hostname = new URL(`http://[${literal}]/`).hostname.replace(/^\[|\]$/g, "");
      expect(isBlockedOutboundAddress(hostname)).toBe(true);
    }
  });

  it("still passes embedded PUBLIC IPv4 (no blanket /96 block)", () => {
    expect(isBlockedOutboundAddress("::ffff:8.8.8.8")).toBe(false);
    expect(isBlockedOutboundAddress("::ffff:0808:0808")).toBe(false);
    expect(isBlockedOutboundAddress("64:ff9b::808:808")).toBe(false);
  });
});

describe("ipInCidr", () => {
  it("matches by value across serializations", () => {
    expect(ipInCidr("::ffff:7f00:1", "::ffff:0:0/96")).toBe(true);
    expect(ipInCidr("::ffff:0808:0808", "::ffff:0:0/96")).toBe(true);
    expect(ipInCidr("64:ff9b::7f00:1", "64:ff9b::/96")).toBe(true);
    expect(ipInCidr("2001:db8::1", "::ffff:0:0/96")).toBe(false);
    expect(ipInCidr("::7f00:1", "::/96")).toBe(true);
  });
});
