import { requireGreaderAuth } from "../../../lib/greader/auth.js";
import { greaderLoaderHandle, greaderActionHandle } from "../../../lib/greader/router.server.js";

export const config = { mode: "app" };

// greader (Google Reader compatible) API: one catch-all router. The path
// grammar is deep and fixed (accounts/ClientLogin, reader/api/0/<endpoint>
// with stream-id PATH segments like stream/contents/feed/<url>), so dispatch
// switches on the decoded splat instead of the filesystem. All logic lives
// in lib/greader/router.server.ts — a .server module, which the framework
// strips from client route chunks, so nothing server-side can leak into the
// browser bundle.
//
// Conventions (SPEC): form-urlencoded bodies via readGreaderParams (getAll
// everywhere — repeated i=/a= keys), JSON by default, text/plain "OK" for
// mutations, loaders THROW their Responses, errors as short text bodies
// with real statuses.

export const middleware = requireGreaderAuth;

export const loader = greaderLoaderHandle;

export const action = greaderActionHandle;
