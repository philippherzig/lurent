# CLAUDE.md

## Non-Discoverable Rules

- **Photo sources: Commons and Pexels built in, Unsplash only with the user's
  own key.** Never ship or share an Unsplash key: their production-key review
  rejected the app outright (their API explicitly bans wallpaper/gallery apps),
  so Unsplash works only with a personal key entered under Settings
  (`Sources/APIKeys.swift`, Keychain). Pixabay rejected it too, citing an app "offering a
  search experience that resembles Pixabay or Canva" — worth knowing before
  reapplying there with different wording, since the reviewer already saw and
  rejected that exact argument. Pexels' *default* key tier needs no review at
  all, only their unlimited tier does — that default tier is what's wired in.
  Its response headers report a 25,000-request window (reset ~30 days out), and
  the documented hourly cap is 200.
  Commons (`Sources/Commons.swift`) needs no API key and no approval. Identify
  with a descriptive User-Agent per Wikimedia's policy, never a bare default one.
  Pexels (`Sources/Pexels.swift`) goes through our own caching Worker at
  `pexels.lurent.app` (`workers/pexels-cache`) unless the user entered a key of
  their own, which goes to api.pexels.com directly. The Worker's key exists only
  as a Worker secret, so the app, `build.sh` and every worktree need no key and
  no `.env` at all.
- **Redeploying the Pexels Worker has traps that each cost hours.**
  `cd workers/pexels-cache && wrangler deploy`. The `CLOUDFLARE_API_TOKEN` in
  `.env` can list Workers but not write them, so deploy through an OAuth login
  (`wrangler login`) — and wrangler reads `.env` from the current directory
  itself, ignoring `env -u`, so run the login from `~`. Caching works only on
  the `pexels.lurent.app` custom domain: `*.workers.dev` stores nothing. Pexels
  answers with `Set-Cookie` headers and Cloudflare never stores a response that
  has one, so the Worker strips them (it also drops `Vary`); remove that and
  caching stops silently, with no error. Never cache a failed response — a
  stored 429 would block search for the whole TTL. To verify: send the same
  search twice and watch `x-ratelimit-remaining`; a hit leaves it unchanged
  and adds an `age` header. Rotating the key: `wrangler secret put
  PEXELS_ACCESS_KEY`.
- **Open source, no App Store.** The Mac App Store move was abandoned in
  November 2026 after repeated App Review rejections; the repo is public under
  MIT. Releases: bump both versions in `Info.plist`, `./build.sh`, `./release.sh`.
  That notarizes, EdDSA-signs the zip with the Sparkle key from the login
  Keychain (back it up: losing it means no build can ever update again), and
  creates a GitHub release carrying `Lurent.zip` + its own `appcast.xml`.
  SUFeedURL is `releases/latest/download/appcast.xml`, so the newest release is
  always the feed. 0.x builds still poll the old R2 feed at
  updates.lurent.app/appcast.xml, which no longer gets updates.
- **CIKernel/CIColorKernel shader gotchas** (`*Processor.swift`, all the
  synthetic styles): `active` is a reserved word and fails compilation with a
  cryptic `expected identifier`; loop increments must be `k += 1`, never
  `k++`; SourceKit reports false `Cannot find … in scope` when it analyzes one
  Processor file in isolation — ignore it and trust `./build.sh`. Kernel
  compile errors only show up at render time, logged by Core Image as
  `[CIKernelPool] <line>:<col>: ERROR: …` (line numbers relative to the kernel
  source string). Never sample a Gaussian-blurred output at *displaced*
  coordinates inside the same kernel — it renders flat-gray garbage that grows
  with the ROI pad; split into separate passes instead (warp → `CIGaussianBlur`
  → shade/composite), each sampling at `destCoord()` only.
