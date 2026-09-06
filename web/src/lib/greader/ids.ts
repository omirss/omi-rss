// Google Reader item-id codec over the omi-rss articles table.
//
// articles.id is a UUID (v4). The greader protocol identifies items by a
// 64-bit signed integer with two wire forms (SPEC 3.4):
//   long:  tag:google.com,2005:reader/item/<16 lowercase hex, zero-padded>
//   short: signed base-10 decimal
//
// Derivation: the 64-bit value is the FIRST 64 BITS of the article UUID —
// hex chars 0-15 of the UUID with dashes removed (aaaaaaaabbbbcccc from
// aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee). Random UUIDv4 bits make this
// collision-safe at self-hosted scale (50% collision odds need ~5e9 items).
// Lookups compare this prefix in SQL, so the mapping is pure and reversible
// per row.
//
// All conversions use BigInt — Number loses precision above 2^53.

const U64 = 2n ** 64n;
const SIGN_BIT = 2n ** 63n;
const MIN_I64 = -(2n ** 63n);
const MAX_I64 = 2n ** 63n - 1n;

export const ITEM_LONG_PREFIX = "tag:google.com,2005:reader/item/";

const LONG_FORM_RE = /^tag:google\.com,2005:reader\/item\/([0-9a-fA-F]{16})$/;
const DECIMAL_RE = /^-?[0-9]{1,19}$/;
const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export function isUuid(value: string): boolean {
  return UUID_RE.test(value);
}

// The 16-hex canonical item key derived from an article UUID.
export function articleHex16(uuid: string): string {
  return uuid.replace(/-/g, "").slice(0, 16).toLowerCase();
}

export function unsignedToSigned(unsigned: bigint): bigint {
  return unsigned >= SIGN_BIT ? unsigned - U64 : unsigned;
}

export function signedToUnsigned(signed: bigint): bigint {
  return signed < 0n ? signed + U64 : signed;
}

export function unsignedToHex16(unsigned: bigint): string {
  return unsigned.toString(16).padStart(16, "0").toLowerCase();
}

export function hex16ToUnsigned(hex16: string): bigint {
  return BigInt(`0x${hex16}`);
}

export function longItemKey(hex16: string): string {
  return ITEM_LONG_PREFIX + hex16;
}

export function shortItemKey(hex16: string): string {
  return unsignedToSigned(hex16ToUnsigned(hex16)).toString();
}

// Parses an incoming item id in EITHER form (all i= params accept both,
// SPEC 3.4) and returns the canonical 16-hex key, or null when malformed.
//
// Disambiguation for pure-digit tokens: a 16-char all-digit string with a
// leading zero is HEX (a zero-padded long-form id); anything else is decimal.
// Negative decimals are valid (high-bit-set hex ids).
export function parseItemKey(input: string): string | null {
  const long = input.match(LONG_FORM_RE);
  if (long) {
    return long[1].toLowerCase();
  }
  if (!DECIMAL_RE.test(input)) {
    return null;
  }
  if (input.length === 16 && input[0] === "0") {
    return input.toLowerCase();
  }
  const signed = BigInt(input);
  if (signed < MIN_I64 || signed > MAX_I64) {
    return null;
  }
  return unsignedToHex16(signedToUnsigned(signed));
}
