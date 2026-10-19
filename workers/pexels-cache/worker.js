// Caches Pexels search/curated results at Cloudflare's edge so many users'
// identical searches share one upstream call instead of one each — Pexels'
// default key tier is 200 requests/hour, shared across every install of the
// app. Also keeps the real Pexels key server-side only: the app talks to
// this Worker, never to api.pexels.com directly, so the key never ships
// inside the app binary.
//
// Uses the Cache API, which only stores anything on a hostname inside our own
// zone (pexels.lurent.app), not on *.workers.dev. The `cf` option on the
// outgoing fetch was tried first and measured as ignored for api.pexels.com.
//
// Routes (mirrors the Pexels v1 API shape the app already expects):
//   GET /search?query=...&per_page=...  -> https://api.pexels.com/v1/search
//   GET /curated?page=...&per_page=...  -> https://api.pexels.com/v1/curated
//
// Deploy:  cd workers/pexels-cache && wrangler deploy
// One-time secret:  wrangler secret put PEXELS_ACCESS_KEY

const ALLOWED_PATHS = new Set(["/search", "/curated"]);
const CACHE_TTL_SECONDS = 6 * 60 * 60; // 6h — Pexels' feeds don't change fast enough to need less

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (!ALLOWED_PATHS.has(url.pathname)) {
      return new Response("Not found", { status: 404 });
    }

    // One logical search must map to one cache entry: the app builds its query
    // string from an unordered dictionary, and "Mountains" / "mountains " are
    // the same search to Pexels.
    const params = new URLSearchParams(url.search);
    const query = params.get("query");
    if (query) params.set("query", query.trim().toLowerCase());
    params.sort();

    const cache = caches.default;
    const cacheKey = new Request(`${url.origin}${url.pathname}?${params}`);

    const cached = await cache.match(cacheKey);
    if (cached) return cached;

    const upstream = new URL(`https://api.pexels.com/v1${url.pathname}`);
    upstream.search = params.toString();

    const upstreamResponse = await fetch(upstream, {
      headers: { Authorization: env.PEXELS_ACCESS_KEY },
    });

    // Never cache failures: a stored 429 would keep the search dead for hours
    // after Pexels' hourly limit has already reset.
    if (!upstreamResponse.ok) return upstreamResponse;

    const response = new Response(upstreamResponse.body, upstreamResponse);
    // Pexels sits behind Cloudflare and answers with its own cookies. A response
    // carrying Set-Cookie is never stored — which silently disabled every earlier
    // caching attempt — and those pexels.com cookies have no business reaching
    // our users anyway. `Vary` is dropped for the same reason: the Cache API only
    // honours Accept-Encoding.
    response.headers.delete("set-cookie");
    response.headers.delete("vary");
    response.headers.set("Cache-Control", `public, max-age=${CACHE_TTL_SECONDS}`);

    ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  },
};
