// greader request/response helpers.
//
// Parameters: greader clients send repeated keys (i=1&i=2, a=...) in the
// urlencoded POST body AND/OR the query string. The house
// Object.fromEntries(searchParams) idiom silently drops repeats — everything
// here uses getAll() and merges query + body (body wins on get()).
//
// Responses: text/plain for ClientLogin, token, OK and error bodies;
// application/json for data endpoints. CORS is served on everything
// (FreshRSS parity; harmless for native clients, useful for browser use).

import { AppError } from "../api/errors.js";

export const GREADER_CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization",
};

export interface GreaderParams {
  get(name: string): string | null;
  getAll(name: string): string[];
}

export async function readGreaderParams(request: Request): Promise<GreaderParams> {
  const entries: Array<[string, string]> = [];
  for (const [name, value] of new URL(request.url).searchParams.entries()) {
    entries.push([name, value]);
  }
  const text = await request.text();
  if (text) {
    for (const [name, value] of new URLSearchParams(text).entries()) {
      entries.push([name, value]);
    }
  }
  const values = new Map<string, string[]>();
  for (const [name, value] of entries) {
    const list = values.get(name);
    if (list) {
      list.push(value);
    } else {
      values.set(name, [value]);
    }
  }
  return {
    get: (name) => {
      const list = values.get(name);
      return list && list.length > 0 ? list[list.length - 1] : null;
    },
    getAll: (name) => values.get(name) ?? [],
  };
}

export function greaderJsonResponse(data: unknown, status: number = 200, extraHeaders?: Record<string, string>): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=UTF-8",
      ...GREADER_CORS_HEADERS,
      ...extraHeaders,
    },
  });
}

export function greaderTextResponse(
  body: string,
  status: number = 200,
  extraHeaders?: Record<string, string>
): Response {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": "text/plain; charset=UTF-8",
      ...GREADER_CORS_HEADERS,
      ...extraHeaders,
    },
  });
}

export function greaderOk(): Response {
  return greaderTextResponse("OK");
}

export function greaderUnauthorized(): Response {
  // FreshRSS-style 401: short plain-text body. Clients treat any 401 as a
  // credentials failure and re-run ClientLogin (or refetch T for POSTs).
  return greaderTextResponse("Unauthorized", 401, { "Google-Bad-Token": "true" });
}

export function greaderBadPostToken(): Response {
  // A present-but-invalid T token: 401 so clients refetch /reader/api/0/token
  // and retry once (NetNewsWire/FeedHQ contract).
  return greaderTextResponse("Unauthorized", 401, {
    "X-Reader-Google-Bad-Token": "true",
    "Google-Bad-Token": "true",
  });
}

export function greaderErrorResponse(error: unknown): Response {
  if (error instanceof Response) {
    return error;
  }
  if (error instanceof AppError) {
    return greaderTextResponse(error.message, error.statusCode);
  }
  console.error("greader handler error:", error);
  return greaderTextResponse("Internal Server Error", 500);
}
