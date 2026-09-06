// greader stream-id grammar (SPEC 3.1-3.3).
//
// Feed stream ids are `feed/<exact feed url>` — the same bytes everywhere
// (subscription/list ids, unread-count ids, origin.streamId, quickadd
// streamId). NetNewsWire joins by raw string equality.
//
// State/label ids always EMIT `user/-/...` but ACCEPT any user-id segment
// (`user/12345/...` — the `-` placeholder convention).

export const STATE_READING_LIST = "reading-list";
export const STATE_READ = "read";
export const STATE_STARRED = "starred";

const QUERYABLE_STATES = new Set([STATE_READING_LIST, STATE_READ, STATE_STARRED]);

export function stateStreamId(state: string): string {
  return `user/-/state/com.google/${state}`;
}

export function labelStreamId(name: string): string {
  return `user/-/label/${name}`;
}

export function feedStreamId(url: string): string {
  return `feed/${url}`;
}

export type ParsedStream =
  | { kind: "state"; state: "reading-list" | "read" | "starred" }
  | { kind: "label"; name: string }
  | { kind: "feed"; token: string };

// Parses an incoming stream id. null = malformed grammar (callers return
// 400). kept-unread/broadcast/like are accepted as edit-tag ACTIONS but not
// served as queryable streams (SPEC 2.16) — they parse to null here.
export function parseStreamId(stream: string): ParsedStream | null {
  const state = stream.match(/^user\/[^/]+\/state\/com\.google\/([a-z-]+)$/);
  if (state) {
    if (QUERYABLE_STATES.has(state[1])) {
      return { kind: "state", state: state[1] as "reading-list" | "read" | "starred" };
    }
    return null;
  }
  const label = stream.match(/^user\/[^/]+\/label\/(.+)$/);
  if (label) {
    return { kind: "label", name: label[1] };
  }
  const feedToken = stream.startsWith("feed/") ? stream.slice("feed/".length) : stream;
  if (feedToken.length > 0) {
    return { kind: "feed", token: feedToken };
  }
  return null;
}

// The greader state/label tags accepted in edit-tag a=/r= lists.
export type EditTag =
  | { kind: "read" }
  | { kind: "starred" }
  | { kind: "noop" };

export function parseEditTag(tag: string): EditTag | null {
  if (tag === stateStreamId(STATE_READ)) {
    return { kind: "read" };
  }
  if (tag === stateStreamId(STATE_STARRED)) {
    return { kind: "starred" };
  }
  // kept-unread, broadcast, like, tracking-kept-unread: accepted, no-op
  // (SPEC 2.12). Item labels (user/-/label/...) are also no-ops: omi-rss has
  // no per-item label table.
  if (/^user\/[^/]+\/(state\/com\.google\/(kept-unread|broadcast|like|tracking-kept-unread)|label\/.+)$/.test(tag)) {
    return { kind: "noop" };
  }
  return null;
}
