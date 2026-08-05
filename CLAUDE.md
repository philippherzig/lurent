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

- **A worktree checkout ships without a working Unsplash key.** `.env` is
  gitignored and per-worktree; only `main`'s `.env` carries the real
  `UNSPLASH_ACCESS_KEY`. `build.sh` builds silently anyway — no error, search
  just returns nothing. Copy `main`'s `.env` before building/releasing from a
  worktree, or build from `main`.
- **Distribution has moved off Sparkle.** Auto-updates were removed
  (`Sources/Updater.swift` is an intentional empty seam) because the app is
  moving to the Mac App Store, which forbids self-updating apps. That move
  isn't live yet — certificates/provisioning are still unchecked in
  `docs/app-store-submission.md` — so shipped builds today are still the
  notarized Developer ID path (`build.sh` → `notarize.sh` → `package.sh`,
  downloaded from lurent.app) with no in-app update mechanism at all.
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
