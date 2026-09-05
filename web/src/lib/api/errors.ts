import { ZodError } from "zod";

// Ported from Express middleware/errorHandler.ts (v0.2.1). /api routes use
// the Express error JSON shape, not RFC 7807 — the Stage-A curl contract and
// byte-parity with the Express server depend on it.

export class AppError extends Error {
  statusCode: number;
  isOperational: boolean;

  constructor(message: string, statusCode: number = 500, isOperational: boolean = true) {
    super(message);
    this.statusCode = statusCode;
    this.isOperational = isOperational;
    Error.captureStackTrace(this, this.constructor);
  }
}

export function jsonResponse(data: unknown, status: number = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

export function noContent(): Response {
  return new Response(null, { status: 204 });
}

// Messages historically thrown with a 500 status that are actually client
// faults (upload type/size limits). errorResponse downgrades these to 400 so
// clients see the right status without every upload route hardcoding it.
const CLIENT_ERROR_MESSAGES = new Set([
  "Only image files are allowed",
  "File too large",
]);

// The Express errorHandler, mapping thrown errors to the same JSON bodies.
export function errorResponse(err: unknown): Response {
  console.error({
    error: err instanceof Error ? err : new Error(String(err)),
  });

  if (err instanceof ZodError) {
    const message = "Validation failed";
    const errors = err.errors.map((e) => ({
      field: e.path.join("."),
      message: e.message,
    }));
    return jsonResponse(
      {
        error: message,
        errors,
        timestamp: new Date().toISOString(),
      },
      400
    );
  }

  if (err instanceof SyntaxError && err.message.includes("JSON")) {
    return jsonResponse(
      {
        error: "Malformed JSON body",
        timestamp: new Date().toISOString(),
      },
      400
    );
  }

  if (err instanceof Error && err.name === "JsonWebTokenError") {
    return jsonResponse(
      {
        error: "Invalid token",
        timestamp: new Date().toISOString(),
      },
      401
    );
  }

  if (err instanceof AppError) {
    const status =
      err.statusCode === 500 && err.message && CLIENT_ERROR_MESSAGES.has(err.message)
        ? 400
        : err.statusCode;
    return jsonResponse(
      {
        error: err.message,
        timestamp: new Date().toISOString(),
      },
      status
    );
  }

  if (err instanceof Error && err.message?.includes("duplicate key")) {
    const field = err.message.match(/Key \((.*?)\)=/)?.[1] || "field";
    return jsonResponse(
      {
        error: "Duplicate value",
        field,
        timestamp: new Date().toISOString(),
      },
      409
    );
  }

  if (err instanceof AppError) {
    return jsonResponse(
      {
        error: err.message,
        timestamp: new Date().toISOString(),
      },
      err.statusCode
    );
  }

  const message = err instanceof Error ? err.message : String(err);
  return jsonResponse(
    {
      error: process.env.NODE_ENV === "production" ? "Internal server error" : message,
      ...(process.env.NODE_ENV !== "production" && {
        stack: err instanceof Error ? err.stack : undefined,
      }),
      timestamp: new Date().toISOString(),
    },
    500
  );
}

// Wrap a route handler the way asyncHandler + errorHandler did in Express.
export function handle(fn: () => Promise<Response>): Promise<Response> {
  return fn().catch((error: unknown) => {
    if (error instanceof Response) {
      return error;
    }
    return errorResponse(error);
  });
}

// Loader variant: the Response must be THROWN, not returned. The dev-mode
// route handler only honors thrown loader Responses for resource routes
// (no default export); returned ones are discarded in favor of a 404.
export async function handleLoader(fn: () => Promise<Response>): Promise<never> {
  throw await handle(fn);
}
