import { createRouter, compileRouteRules, resolveRouteRuleRedirect, resolveRouteRuleRewrite, resolveRouteRuleHeaders, renderAppRoute, isMutationMethod, createMemoryLoaderCacheStore } from "@neutron-build/core/runtime-edge";
import * as __globalMiddlewareModule from "../../src/middleware.ts";
import * as routeModule0 from "../../src/routes/_layout.tsx";
import * as routeModule1 from "../../src/routes/index.tsx";
import * as routeModule2 from "../../src/routes/analytics.tsx";
import * as routeModule3 from "../../src/routes/api/_layout.tsx";
import * as routeModule4 from "../../src/routes/discover.tsx";
import * as routeModule5 from "../../src/routes/folders.tsx";
import * as routeModule6 from "../../src/routes/health.tsx";
import * as routeModule7 from "../../src/routes/login.tsx";
import * as routeModule8 from "../../src/routes/ready.tsx";
import * as routeModule9 from "../../src/routes/saved.tsx";
import * as routeModule10 from "../../src/routes/search.tsx";
import * as routeModule11 from "../../src/routes/settings.tsx";
import * as routeModule12 from "../../src/routes/statistics.tsx";
import * as routeModule13 from "../../src/routes/api/[...path].tsx";
import * as routeModule14 from "../../src/routes/api/analytics/index.tsx";
import * as routeModule15 from "../../src/routes/api/articles/index.tsx";
import * as routeModule16 from "../../src/routes/api/feeds/index.tsx";
import * as routeModule17 from "../../src/routes/api/folders/index.tsx";
import * as routeModule18 from "../../src/routes/api/ping.tsx";
import * as routeModule19 from "../../src/routes/uploads/[...path].tsx";
import * as routeModule20 from "../../src/routes/api/analytics/article-read.tsx";
import * as routeModule21 from "../../src/routes/api/analytics/export.tsx";
import * as routeModule22 from "../../src/routes/api/analytics/feed-interaction.tsx";
import * as routeModule23 from "../../src/routes/api/analytics/streaks.tsx";
import * as routeModule24 from "../../src/routes/api/articles/batch-update.tsx";
import * as routeModule25 from "../../src/routes/api/articles/mark-all-read.tsx";
import * as routeModule26 from "../../src/routes/api/auth/forgot-password.tsx";
import * as routeModule27 from "../../src/routes/api/auth/login.tsx";
import * as routeModule28 from "../../src/routes/api/auth/logout.tsx";
import * as routeModule29 from "../../src/routes/api/auth/refresh.tsx";
import * as routeModule30 from "../../src/routes/api/auth/register.tsx";
import * as routeModule31 from "../../src/routes/api/auth/reset-password.tsx";
import * as routeModule32 from "../../src/routes/api/discovery/categories.tsx";
import * as routeModule33 from "../../src/routes/api/discovery/discover.tsx";
import * as routeModule34 from "../../src/routes/api/discovery/search.tsx";
import * as routeModule35 from "../../src/routes/api/discovery/validate.tsx";
import * as routeModule36 from "../../src/routes/api/folders/reorder.tsx";
import * as routeModule37 from "../../src/routes/api/stats/history.tsx";
import * as routeModule38 from "../../src/routes/api/stats/overview.tsx";
import * as routeModule39 from "../../src/routes/api/stats/reading-time.tsx";
import * as routeModule40 from "../../src/routes/api/users/me.tsx";
import * as routeModule41 from "../../src/routes/api/articles/[articleId].tsx";
import * as routeModule42 from "../../src/routes/api/feeds/[feedId].tsx";
import * as routeModule43 from "../../src/routes/api/folders/[folderId].tsx";
import * as routeModule44 from "../../src/routes/api/discovery/export/opml.tsx";
import * as routeModule45 from "../../src/routes/api/discovery/import/opml.tsx";
import * as routeModule46 from "../../src/routes/api/users/me/avatar.tsx";
import * as routeModule47 from "../../src/routes/api/users/me/password.tsx";
import * as routeModule48 from "../../src/routes/api/users/me/settings.tsx";
import * as routeModule49 from "../../src/routes/api/auth/verify-email/[token].tsx";
import * as routeModule50 from "../../src/routes/api/discovery/related/[feedId].tsx";
import * as routeModule51 from "../../src/routes/api/articles/[articleId]/state.tsx";
import * as routeModule52 from "../../src/routes/api/feeds/[feedId]/mark-all-read.tsx";
import * as routeModule53 from "../../src/routes/api/feeds/[feedId]/refresh.tsx";

const CLIENT_ENTRY_SCRIPT_SRC = "/assets/index-BJEBfnaV.js";
const CLIENT_STYLESHEET_HREFS = ["/assets/_layout-C0QCKq8n.css","/assets/reading-mhXLwx_U.css","/assets/widgets-BTB-VTYI.css"];
const ROUTE_RULES = compileRouteRules({});

const ROUTE_DEFS = [
  {
    id: "route:_layout.tsx",
    path: "/",
    parentId: null,
    params: [],
    mode: "static",
    cache: null,
    isLayout: true,
  },
  {
    id: "route:index.tsx",
    path: "/",
    parentId: "route:_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:analytics.tsx",
    path: "/analytics",
    parentId: "route:_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/_layout.tsx",
    path: "/api",
    parentId: "route:_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: true,
  },
  {
    id: "route:discover.tsx",
    path: "/discover",
    parentId: "route:_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:folders.tsx",
    path: "/folders",
    parentId: "route:_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:health.tsx",
    path: "/health",
    parentId: "route:_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:login.tsx",
    path: "/login",
    parentId: "route:_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:ready.tsx",
    path: "/ready",
    parentId: "route:_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:saved.tsx",
    path: "/saved",
    parentId: "route:_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:search.tsx",
    path: "/search",
    parentId: "route:_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:settings.tsx",
    path: "/settings",
    parentId: "route:_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:statistics.tsx",
    path: "/statistics",
    parentId: "route:_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/[...path].tsx",
    path: "/api/*path",
    parentId: "route:api/_layout.tsx",
    params: ["path"],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/analytics/index.tsx",
    path: "/api/analytics",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/articles/index.tsx",
    path: "/api/articles",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/feeds/index.tsx",
    path: "/api/feeds",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/folders/index.tsx",
    path: "/api/folders",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/ping.tsx",
    path: "/api/ping",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:uploads/[...path].tsx",
    path: "/uploads/*path",
    parentId: "route:_layout.tsx",
    params: ["path"],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/analytics/article-read.tsx",
    path: "/api/analytics/article-read",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/analytics/export.tsx",
    path: "/api/analytics/export",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/analytics/feed-interaction.tsx",
    path: "/api/analytics/feed-interaction",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/analytics/streaks.tsx",
    path: "/api/analytics/streaks",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/articles/batch-update.tsx",
    path: "/api/articles/batch-update",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/articles/mark-all-read.tsx",
    path: "/api/articles/mark-all-read",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/auth/forgot-password.tsx",
    path: "/api/auth/forgot-password",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/auth/login.tsx",
    path: "/api/auth/login",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/auth/logout.tsx",
    path: "/api/auth/logout",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/auth/refresh.tsx",
    path: "/api/auth/refresh",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/auth/register.tsx",
    path: "/api/auth/register",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/auth/reset-password.tsx",
    path: "/api/auth/reset-password",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/discovery/categories.tsx",
    path: "/api/discovery/categories",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/discovery/discover.tsx",
    path: "/api/discovery/discover",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/discovery/search.tsx",
    path: "/api/discovery/search",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/discovery/validate.tsx",
    path: "/api/discovery/validate",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/folders/reorder.tsx",
    path: "/api/folders/reorder",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/stats/history.tsx",
    path: "/api/stats/history",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/stats/overview.tsx",
    path: "/api/stats/overview",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/stats/reading-time.tsx",
    path: "/api/stats/reading-time",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/users/me.tsx",
    path: "/api/users/me",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/articles/[articleId].tsx",
    path: "/api/articles/:articleId",
    parentId: "route:api/_layout.tsx",
    params: ["articleId"],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/feeds/[feedId].tsx",
    path: "/api/feeds/:feedId",
    parentId: "route:api/_layout.tsx",
    params: ["feedId"],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/folders/[folderId].tsx",
    path: "/api/folders/:folderId",
    parentId: "route:api/_layout.tsx",
    params: ["folderId"],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/discovery/export/opml.tsx",
    path: "/api/discovery/export/opml",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/discovery/import/opml.tsx",
    path: "/api/discovery/import/opml",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/users/me/avatar.tsx",
    path: "/api/users/me/avatar",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/users/me/password.tsx",
    path: "/api/users/me/password",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/users/me/settings.tsx",
    path: "/api/users/me/settings",
    parentId: "route:api/_layout.tsx",
    params: [],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/auth/verify-email/[token].tsx",
    path: "/api/auth/verify-email/:token",
    parentId: "route:api/_layout.tsx",
    params: ["token"],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/discovery/related/[feedId].tsx",
    path: "/api/discovery/related/:feedId",
    parentId: "route:api/_layout.tsx",
    params: ["feedId"],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/articles/[articleId]/state.tsx",
    path: "/api/articles/:articleId/state",
    parentId: "route:api/_layout.tsx",
    params: ["articleId"],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/feeds/[feedId]/mark-all-read.tsx",
    path: "/api/feeds/:feedId/mark-all-read",
    parentId: "route:api/_layout.tsx",
    params: ["feedId"],
    mode: "app",
    cache: null,
    isLayout: false,
  },
  {
    id: "route:api/feeds/[feedId]/refresh.tsx",
    path: "/api/feeds/:feedId/refresh",
    parentId: "route:api/_layout.tsx",
    params: ["feedId"],
    mode: "app",
    cache: null,
    isLayout: false,
  },
];

const ROUTE_MODULES = {
  "route:_layout.tsx": routeModule0,
  "route:index.tsx": routeModule1,
  "route:analytics.tsx": routeModule2,
  "route:api/_layout.tsx": routeModule3,
  "route:discover.tsx": routeModule4,
  "route:folders.tsx": routeModule5,
  "route:health.tsx": routeModule6,
  "route:login.tsx": routeModule7,
  "route:ready.tsx": routeModule8,
  "route:saved.tsx": routeModule9,
  "route:search.tsx": routeModule10,
  "route:settings.tsx": routeModule11,
  "route:statistics.tsx": routeModule12,
  "route:api/[...path].tsx": routeModule13,
  "route:api/analytics/index.tsx": routeModule14,
  "route:api/articles/index.tsx": routeModule15,
  "route:api/feeds/index.tsx": routeModule16,
  "route:api/folders/index.tsx": routeModule17,
  "route:api/ping.tsx": routeModule18,
  "route:uploads/[...path].tsx": routeModule19,
  "route:api/analytics/article-read.tsx": routeModule20,
  "route:api/analytics/export.tsx": routeModule21,
  "route:api/analytics/feed-interaction.tsx": routeModule22,
  "route:api/analytics/streaks.tsx": routeModule23,
  "route:api/articles/batch-update.tsx": routeModule24,
  "route:api/articles/mark-all-read.tsx": routeModule25,
  "route:api/auth/forgot-password.tsx": routeModule26,
  "route:api/auth/login.tsx": routeModule27,
  "route:api/auth/logout.tsx": routeModule28,
  "route:api/auth/refresh.tsx": routeModule29,
  "route:api/auth/register.tsx": routeModule30,
  "route:api/auth/reset-password.tsx": routeModule31,
  "route:api/discovery/categories.tsx": routeModule32,
  "route:api/discovery/discover.tsx": routeModule33,
  "route:api/discovery/search.tsx": routeModule34,
  "route:api/discovery/validate.tsx": routeModule35,
  "route:api/folders/reorder.tsx": routeModule36,
  "route:api/stats/history.tsx": routeModule37,
  "route:api/stats/overview.tsx": routeModule38,
  "route:api/stats/reading-time.tsx": routeModule39,
  "route:api/users/me.tsx": routeModule40,
  "route:api/articles/[articleId].tsx": routeModule41,
  "route:api/feeds/[feedId].tsx": routeModule42,
  "route:api/folders/[folderId].tsx": routeModule43,
  "route:api/discovery/export/opml.tsx": routeModule44,
  "route:api/discovery/import/opml.tsx": routeModule45,
  "route:api/users/me/avatar.tsx": routeModule46,
  "route:api/users/me/password.tsx": routeModule47,
  "route:api/users/me/settings.tsx": routeModule48,
  "route:api/auth/verify-email/[token].tsx": routeModule49,
  "route:api/discovery/related/[feedId].tsx": routeModule50,
  "route:api/articles/[articleId]/state.tsx": routeModule51,
  "route:api/feeds/[feedId]/mark-all-read.tsx": routeModule52,
  "route:api/feeds/[feedId]/refresh.tsx": routeModule53,
};

const APP_ROUTE_IDS = new Set(["route:index.tsx","route:analytics.tsx","route:discover.tsx","route:folders.tsx","route:health.tsx","route:login.tsx","route:ready.tsx","route:saved.tsx","route:search.tsx","route:settings.tsx","route:statistics.tsx","route:api/[...path].tsx","route:api/analytics/index.tsx","route:api/articles/index.tsx","route:api/feeds/index.tsx","route:api/folders/index.tsx","route:api/ping.tsx","route:uploads/[...path].tsx","route:api/analytics/article-read.tsx","route:api/analytics/export.tsx","route:api/analytics/feed-interaction.tsx","route:api/analytics/streaks.tsx","route:api/articles/batch-update.tsx","route:api/articles/mark-all-read.tsx","route:api/auth/forgot-password.tsx","route:api/auth/login.tsx","route:api/auth/logout.tsx","route:api/auth/refresh.tsx","route:api/auth/register.tsx","route:api/auth/reset-password.tsx","route:api/discovery/categories.tsx","route:api/discovery/discover.tsx","route:api/discovery/search.tsx","route:api/discovery/validate.tsx","route:api/folders/reorder.tsx","route:api/stats/history.tsx","route:api/stats/overview.tsx","route:api/stats/reading-time.tsx","route:api/users/me.tsx","route:api/articles/[articleId].tsx","route:api/feeds/[feedId].tsx","route:api/folders/[folderId].tsx","route:api/discovery/export/opml.tsx","route:api/discovery/import/opml.tsx","route:api/users/me/avatar.tsx","route:api/users/me/password.tsx","route:api/users/me/settings.tsx","route:api/auth/verify-email/[token].tsx","route:api/discovery/related/[feedId].tsx","route:api/articles/[articleId]/state.tsx","route:api/feeds/[feedId]/mark-all-read.tsx","route:api/feeds/[feedId]/refresh.tsx"]);
const ROUTE_DEF_BY_ID = new Map(ROUTE_DEFS.map((route) => [route.id, route]));
const ROUTES_BY_ID = new Map(ROUTE_DEFS.map((route) => [route.id, toRuntimeRoute(route)]));
const LOADER_DATA_CACHE = createMemoryLoaderCacheStore();
const GLOBAL_MIDDLEWARE = (() => {
  const __gmExport = __globalMiddlewareModule.middleware ?? __globalMiddlewareModule.default;
  return typeof __gmExport === 'function' ? [__gmExport] : (Array.isArray(__gmExport) ? __gmExport.filter((f) => typeof f === 'function') : []);
})();

const router = createRouter();
for (const routeDef of ROUTE_DEFS) {
  if (!routeDef.isLayout && APP_ROUTE_IDS.has(routeDef.id)) {
    router.insert(toRuntimeRoute(routeDef));
  }
}

let __requestSeq = 0;

async function handleNeutronRequestInner(request) {
  const requestUrl = new URL(request.url);
  const pathname = normalizePathname(requestUrl.pathname);
  if (!pathname) {
    return new Response("Bad Request", { status: 400 });
  }

  const redirect = resolveRouteRuleRedirect(ROUTE_RULES, pathname, requestUrl.search);
  if (redirect) {
    return new Response(null, {
      status: redirect.status,
      headers: {
        Location: redirect.location,
      },
    });
  }

  const rewrite = resolveRouteRuleRewrite(ROUTE_RULES, pathname);
  const effectivePathname = rewrite?.pathname || pathname;

  const match = router.match(effectivePathname);
  if (!match || !APP_ROUTE_IDS.has(match.route.id)) {
    return new Response("Not Found", { status: 404 });
  }

  const layouts = getLayoutChain(match.route);
  const allRoutes = [...layouts, match.route];
  const routeModules = new Map();
  for (const route of allRoutes) {
    routeModules.set(route.id, ROUTE_MODULES[route.id] || {});
  }

  if (isMutationMethod(request.method)) {
    await LOADER_DATA_CACHE.deleteByPath(effectivePathname);
  }

  const response = await renderAppRoute(
    request,
    { route: match.route, params: match.params, layouts },
    routeModules,
    {
      clientEntryScriptSrc: CLIENT_ENTRY_SCRIPT_SRC,
      stylesheetHrefs: CLIENT_STYLESHEET_HREFS,
      loaderDataCache: LOADER_DATA_CACHE,
      requestTrace: {
        requestId: String(++__requestSeq),
        method: request.method,
        pathname: effectivePathname,
      },
      globalMiddleware: GLOBAL_MIDDLEWARE,
    }
  );

  if (isMutationMethod(request.method)) {
    await applyMutationInvalidationToLoaderDataCache(effectivePathname, response);
  }

  applyRouteRuleHeaders(response, pathname);
  return response;
}

function toRuntimeRoute(routeDef) {
  const config = { mode: routeDef.mode };
  if (routeDef.cache) {
    config.cache = routeDef.cache;
  }

  return {
    id: routeDef.id,
    path: routeDef.path,
    file: routeDef.id,
    pattern: /^$/,
    params: routeDef.params,
    config,
    parentId: routeDef.parentId,
  };
}

function getLayoutChain(route) {
  const layouts = [];
  let parentId = route.parentId;
  while (parentId) {
    const routeDef = ROUTE_DEF_BY_ID.get(parentId);
    if (!routeDef) {
      break;
    }
    if (routeDef.isLayout) {
      const layoutRoute = ROUTES_BY_ID.get(routeDef.id);
      if (layoutRoute) {
        layouts.unshift(layoutRoute);
      }
    }
    parentId = routeDef.parentId;
  }
  return layouts;
}

function normalizePathname(pathname) {
  let decoded;
  try {
    decoded = decodeURIComponent(pathname || "/");
  } catch {
    return null;
  }

  if (!decoded.startsWith("/") || decoded.includes("..")) {
    return null;
  }
  if (decoded.length > 1 && decoded.endsWith("/")) {
    return decoded.slice(0, -1);
  }
  return decoded;
}

function applyRouteRuleHeaders(response, pathname) {
  const matches = resolveRouteRuleHeaders(ROUTE_RULES, pathname);
  for (const match of matches) {
    for (const [name, value] of Object.entries(match.headers || {})) {
      try {
        if (!response.headers.has(name)) {
          response.headers.set(name, String(value));
        }
      } catch {
        // Ignore immutable Response headers (for example, redirect responses).
      }
    }
  }
}

async function applyMutationInvalidationToLoaderDataCache(pathname, response) {
  const directive = response.headers.get("x-neutron-invalidate");
  if (!directive) {
    return;
  }

  const tokens = directive
    .split(",")
    .map((token) => token.trim())
    .filter(Boolean);

  if (tokens.length === 0) {
    return;
  }

  for (const token of tokens) {
    if (token === "*") {
      await LOADER_DATA_CACHE.clear();
      return;
    }
    if (token === "self") {
      await LOADER_DATA_CACHE.deleteByPath(pathname);
      continue;
    }
    const normalized = normalizePathname(token);
    if (normalized) {
      await LOADER_DATA_CACHE.deleteByPath(normalized);
    }
  }
}

// Apply baseline security headers to every response from the production handler
// (the dev server does this already; the generated handler must match).
export async function handleNeutronRequest(request) {
  const response = await handleNeutronRequestInner(request);
  const defaults = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "strict-origin-when-cross-origin",
  };
  for (const [name, value] of Object.entries(defaults)) {
    if (!response.headers.has(name)) {
      response.headers.set(name, value);
    }
  }
  return response;
}
