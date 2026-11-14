# CLAUDE.md

## Working Approach

- **Answer short, lead with the recommendation**: open with the recommendation
  and next steps, not the reasoning that produced them. Don't restate the
  request, don't narrate what you're about to do, don't summarize what the
  diff already shows, don't list options you're not recommending. One
  recommendation — alternatives only when the user has to choose.
- **One question, one answer.** Answer what was asked and stop. Not the
  neighbouring question, not the follow-up you expect. If a second thing
  genuinely matters, it's one sentence at the end, never its own section.
- **Never hand a lookup back to the user.** If it's knowable from the repo,
  the diff, or the tools available, go and know it. A question to the user is
  for a decision that's theirs, never for information you could retrieve.
- **A reply is prose, not a document.** Tables, bold run-in headers, and
  nested bullets belong in files and specs — not in a chat answer. If it seems
  to need a table to stay readable, it needs to be shorter instead.
- **Stop closing with an offer.** Ending with "soll ich auch…?" turns every
  answer into a decision the user has to make. Do the obvious work and say so
  in a clause; silence at the end of an answer is fine.
- **Don't offer what you could just do.** A proposal that makes sense is
  work, not a question: do it, in the same change, and say what you did.
  Next-steps are for decisions only the user can make — everything else is
  yours.
- **Default to the clean solution, not the quick fix**, but follow YAGNI: no
  speculative abstractions, config knobs, or "might need this later" code for
  needs the current change doesn't have.

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
  MIT. Builds ship through the notarized Developer ID path (`build.sh` →
  `notarize.sh` → `package.sh`). Sparkle auto-updates were removed for the
  Store and not brought back (`Sources/Updater.swift` is an empty seam), so
  there is no in-app update mechanism.
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
