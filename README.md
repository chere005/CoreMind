# CoreMind

The canonical home of everything the Mind-suite apps share, and the check
that keeps their copies honest.

**This is a reference repo, not a runtime dependency.** Nothing imports it,
nothing links against it, and it ships to no platform. The suite's doctrine —
written independently into CalMind's, ChefMind's, MyCalMind's and AcctMind's
own rules — is that apps CLONE shared code and CHECKS keep the clones in
lockstep. A shared npm package would force the editions' deliberate seams
(ChefMind adds shopping, MyCalMind subtracts the server) into config and
plugin abstractions, add a build step where none exists, and replace
verifiable bytes with trusted version ranges. So CoreMind does the opposite:
it holds the bytes once, says exactly who mirrors them, and proves the
mirrors match.

## The consumers

| repo | what it is | shares |
|---|---|---|
| [CalMind](https://github.com/chere005/CalMind) | the origin: calendar/reminders/notes/habits/recipes, web+iOS+Android+macOS+watch | everything |
| [ChefMind](https://github.com/chere005/ChefMind) | recipes + shopping list on CalMind's server, kept apart by a sync space | core, spec, app layer, tools, desktop |
| [MyCalMind](https://github.com/chere005/MyCalMind) | CalMind with the server taken out; iOS+watch, Bonjour mirroring | core, spec, app layer |
| [AcctMind](https://github.com/chere005/AcctMind) | the ledger — a sibling RE-IMPLEMENTATION of the architecture, not a clone | desktop shell only |

AcctMind is the deliberate outlier: its core shares zero byte-identical files
with the lineage repos (its own `AGENTS.md` forbids importing from them). It
participates here only through the desktop-shell files, and as the named
source of ideas worth upstreaming — its `stable()` is CalMind's `canon()`
with an extra fix, its `patch-web-html` stamps a build.json, its core
tsconfig splits tests out with `"types": []`.

## The map

```
canon/            The canonical bytes, laid out exactly as consumers carry
                  them: packages/core (src + test), spec/, app/ (src,
                  index.ts, tsconfig), tools/, desktop/, tsconfig.base.json.
consumers/*.tsv   One manifest per consumer: mode, canon path, local path,
                  note. Modes: `exact` (byte-identical, drift FAILS the
                  check), `fork` (deliberate divergence, reported), `owed`
                  (verified lag — the copy-down work list).
bin/check-drift.sh  The check. Run it from anywhere; consumers are expected
                  as sibling checkouts (MIND_DIR overrides the parent).
```

```sh
npm install
npm test          # the canon core suite itself: 634 tests, run HERE —
                  # proving the canonical set is coherent, not just copied
npm run typecheck
npm run check     # every consumer with a checkout, against canon
```

## How a shared fix flows

1. The fix lands in **CalMind** (the origin) — or, where another repo's copy
   is genuinely ahead, it is promoted INTO canon here first.
2. The same bytes are copied into `canon/` and into each consumer listed for
   that file — a deliberate act, per repo, exactly as the clones' own
   "copied down" rule has always worked.
3. `npm run check` proves the propagation happened. A red `exact` row is
   drift; an `owed` row is the check keeping score until the copy lands.

Canon is CalMind's copy for every file except where the analysis found a
strict superset elsewhere: `core/src/recipe.ts` is ChefMind's (it exports
four helpers for shopping.ts — a no-op for everyone else), and adopting it
upstream is the current `owed` row on CalMind.

## What is deliberately NOT here

- **Each edition's seams**: `core/src/index.ts` barrels (the export set IS
  the edition — CalMind's rides along only so the canon suite can run),
  `store.tsx`, `chrome.tsx`, per-app screens that diverged by design.
- **Single-owner modules**: ChefMind's `shopping.ts`, MyCalMind's
  `fetchguard.ts`/`recipefetch.ts`/`peer.ts`, CalMind's request/QuickTick
  surface.
- **AcctMind's core and spec** — a re-implementation, documented above.
- **Deploy scripts and their guard provers** — three genuinely different
  scripts sharing doctrine, not code: per-app destination tables ARE the app.
- **The server** — CalMind's alone, by design; ChefMind rides it via the
  sync space.

Born 2026-08-22 from a four-repo, hash-verified analysis (every `exact` row
was byte-compared in every listed repo; the fork and owed notes were
spot-diffed). The `owed` rows at birth are the analysis' findings, kept as
the check's opening work list rather than papered over.
