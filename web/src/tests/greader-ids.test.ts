import { describe, it, expect } from "vitest";
import {
  articleHex16,
  hex16ToUnsigned,
  isUuid,
  longItemKey,
  parseItemKey,
  shortItemKey,
  signedToUnsigned,
  unsignedToHex16,
  unsignedToSigned,
} from "../lib/greader/ids.js";

// Item-id codec contracts (SPEC 3.4). Conversion vectors are Google's own
// wiki examples — including the negative (high-bit) cases FreshRSS gets
// wrong. Everything through BigInt; Number loses precision past 2^53.

describe("greader id codec", () => {
  const vectors: Array<[string, string]> = [
    ["5d0cfa30041d4348", "6705009029382226760"],
    ["024025978b5e50d2", "162170919393841362"],
    ["fb115bd6d34a8e9f", "-355401917359550817"],
    ["000088960000047a", "150177826473082"],
    ["80484b00000e8003", "-9203023375158575101"],
  ];

  it("converts the verified hex<->decimal vectors", () => {
    for (const [hex16, decimal] of vectors) {
      expect(shortItemKey(hex16)).toBe(decimal);
      expect(parseItemKey(decimal)).toBe(hex16);
      expect(parseItemKey(longItemKey(hex16))).toBe(hex16);
    }
  });

  it("zero-pads the long form to 16 hex chars", () => {
    expect(unsignedToHex16(BigInt("150177826473082"))).toBe("000088960000047a");
    expect(longItemKey("000088960000047a")).toBe(
      "tag:google.com,2005:reader/item/000088960000047a"
    );
  });

  it("signed<->unsigned round trips at the 64-bit boundaries", () => {
    expect(unsignedToSigned(2n ** 63n)).toBe(-(2n ** 63n));
    expect(signedToUnsigned(-(2n ** 63n))).toBe(2n ** 63n);
    expect(unsignedToSigned(2n ** 64n - 1n)).toBe(-1n);
    expect(signedToUnsigned(-1n)).toBe(2n ** 64n - 1n);
    expect(hex16ToUnsigned("ffffffffffffffff")).toBe(2n ** 64n - 1n);
  });

  it("derives the item key from the first 64 bits of the article uuid", () => {
    expect(articleHex16("aaaaaaaabbbbcccc-dddd-eeeeeeeeeeee")).toBe("aaaaaaaabbbbcccc");
    expect(articleHex16("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")).toBe("aaaaaaaabbbbcccc");
  });

  it("accepts negative decimal input ids", () => {
    expect(parseItemKey("-355401917359550817")).toBe("fb115bd6d34a8e9f");
    expect(parseItemKey("-1")).toBe("ffffffffffffffff");
  });

  it("treats a 16-char all-digit leading-zero token as hex, not decimal", () => {
    expect(parseItemKey("0123456789012345")).toBe("0123456789012345");
    expect(parseItemKey("1234567890123456")).not.toBe("1234567890123456");
    expect(parseItemKey("1234567890123456")).toBe(unsignedToHex16(BigInt("1234567890123456")));
  });

  it("rejects malformed and out-of-range ids", () => {
    expect(parseItemKey("")).toBeNull();
    expect(parseItemKey("tag:google.com,2005:reader/item/xyz")).toBeNull();
    expect(parseItemKey("tag:google.com,2005:reader/item/5d0cfa30041d434")).toBeNull();
    expect(parseItemKey("5d0cfa30041d4348z")).toBeNull();
    expect(parseItemKey("9999999999999999999")).toBeNull(); // > 2^63-1
    expect(parseItemKey("-9999999999999999999")).toBeNull(); // < -(2^63)
  });

  it("recognizes uuids", () => {
    expect(isUuid("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")).toBe(true);
    expect(isUuid("feed/https://example.com/a.xml")).toBe(false);
    expect(isUuid("not-a-uuid")).toBe(false);
  });
});
