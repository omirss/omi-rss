import { describe, it, expect } from "vitest";
import { z } from "zod";
import { validationFailure } from "./validate.js";

describe("validationFailure envelope", () => {
  it("matches the errors.ts shape (error, errors[], timestamp) at 400", async () => {
    const schema = z.object({ q: z.string().min(2) });
    const parsed = schema.safeParse({});
    if (parsed.success) {
      throw new Error("expected parse failure");
    }

    const response = validationFailure(parsed.error);
    expect(response.status).toBe(400);
    expect(response.headers.get("Content-Type")).toContain("application/json");

    const body = JSON.parse(await response.text()) as Record<string, unknown>;
    expect(body.error).toBe("Validation failed");
    expect(Array.isArray(body.errors)).toBe(true);
    expect(body.errors).toEqual([{ field: "q", message: expect.any(String) }]);
    expect(typeof body.timestamp).toBe("string");
    expect("success" in body).toBe(false);
  });
});
