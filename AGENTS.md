# Working in CoreMind

The baseline for all of Sean's repos lives in ~/GIT/AgentSuite/AGENTS.md
and is imported here; this file holds only what is true of THIS repo.
@../AgentSuite/AGENTS.md

The canonical home of what the Mind-suite apps share. `README.md` is the map
and the doctrine; this file is how to work in here.

## Standing rules

- **This repo never becomes a dependency.** No app imports it, links it, or
  installs it. The suite clones and checks — a CoreMind that apps imported
  would be a build step and a trust relationship, which is exactly what the
  consumers' own rules refuse. If that ever changes, it changes in the
  consumers' AGENTS.md files first, on Sean's word.
- **Canon changes are copies, not edits.** A shared fix lands in its home
  repo (CalMind, unless a superset genuinely lives elsewhere), then the SAME
  BYTES are copied here and to every consumer that mirrors the file. Editing
  canon by hand to something no repo carries makes the check lie about
  everyone at once. The one exception is promoting a verified superset into
  canon — which is a copy too, just from a different repo.
- **The manifests are hand-kept and load-bearing.** consumers/*.tsv rows are
  mode/canon/local/note, tab-separated. `exact` rows FAIL the check on
  drift; `owed` rows are verified lags awaiting a copy-down (promote to
  `exact` when it lands); `fork` rows are deliberate divergences whose note
  says why. A row's mode is a claim about intent — never demote a failing
  `exact` to `fork` to make the check green; that is deleting the alarm.
- **Run all three before committing**: `npm test` (the canon suite, 634
  tests — proof the canonical set coheres), `npm run typecheck`, and
  `npm run check` against the sibling checkouts.
- **The deploy graph lives in one place.** `bin/deploy.sh` and `bin/dtp.sh`
  each carry the same `downstream_of()` and the same `ORDER`, and both are
  the reason ChefMind cannot ship before the API it checks. Add an edge to
  one and add it to the other in the same commit — two graphs that disagree
  is worse than the memory this replaced. A deploy CASCADES by default;
  `--only` is the way to ship one thing.
- **`npm run dtp` / `npm run tdtp` wrap `bin/dtp.sh`, the suite orchestrator
  this repo owns** — not a per-repo release script like the four apps have.
  dtp deploys, tags, and pushes each targeted repo's own lane, in
  `bin/deploy.sh`'s order; tdtp (`--full`) runs each repo's own test suite
  first. Unlike the apps, there is no default target — pass one after `--`:
  `npm run dtp -- core` (CoreMind alone — propagate canon,
  `bin/check-drift.sh`, tag, push, no cascade), `npm run dtp -- all` (every
  repo, core first), or `npm run tdtp -- all --platforms` (test-first, whole
  suite, plus the platform builds no repo's own deploy ships — see
  Platforms). Core's own lane bumps its minor version only on a tag
  collision, otherwise it tags whatever `package.json` already says.
- **`deploy-core.sh` writes over app source and commits nothing.** It refuses
  a dirty consumer (two changes in one diff has no way back), never touches a
  `fork` row, leaves `owed` rows alone unless asked, refuses the BLOCKED one
  by name, and runs each touched app's own typecheck and core suite before
  claiming the copy landed.
- **A live send is a host's config change, never a canon edit.** Canon's mail
  transport (`canon/server/lib/mail.php`) stays commented out beside the stub.

## Platforms

CoreMind ships nothing of its own — no server, no app, no platform build; it
tags itself and stops. What it owns is `bin/build-platforms.sh`, the shared,
table-driven script that builds the platforms none of the four apps' own
deploy ships by itself:

- **macOS** — a Tauri desktop bundle for CalMind, ChefMind and AcctMind, and
  a real **Mac Catalyst** app for MyCalMind, which has no Tauri shell. All four
  are copied into `/Applications` and the copy is verified; the install step
  was missing until 2026-08-22, which is why "i don't see chefmind on macos"
  was true of every app at once and of none of their builds.

  Catalyst took 26 attempts and four distinct causes, all now handled by the
  script plus MyCalMind's own `withMacCatalyst` config plugin: the widget
  target needed `SUPPORTS_MACCATALYST` too; there is no x86_64 Catalyst slice
  upstream, so the build is arm64-only; Expo's and RN's prebuilt XCFrameworks
  ship no maccatalyst copy, so it builds from source
  (`EXPO_USE_PRECOMPILED_MODULES=0 RCT_USE_PREBUILT_RNCORE=0`); and the
  vendored ReactNativeDependencies bundle is malformed for that slice.

  **That last repair is not durable yet.** The `[CP-User] [RNDeps]` script
  phase is `alwaysOutOfDate`, so it re-extracts the pristine bundle mid-build
  and undoes anything fixed beforehand — which is why the repair is PATCHED
  INTO that phase by `bin/patch-rndeps-catalyst.js` rather than run before it.
  The patch is idempotent and re-applied on every build, but it is a patch to
  generated output: a fresh `expo prebuild` rewrites the pbxproj and the
  script has to run again. It does, from here; the thing to know is that
  nothing upstream has been fixed.
- **iOS** — installs to the one physical iPhone via `devicectl`, for CalMind,
  ChefMind, and AcctMind (that phone's free-tier cap is 3 installed apps,
  already spent on those three; CalMind's install also carries its watch
  companion app onto a paired Apple Watch when one is reachable). MyCalMind's
  iOS build is BUILD ONLY — it deliberately does not install, to leave that
  3rd device slot alone; its own `tools/deploy-device.sh` is the real install
  path, run only when MyCalMind should occupy the slot.
- **Android** — builds, installs, and launches on a local emulator (or
  connected hardware), for all four apps: CalMind, ChefMind, AcctMind, and
  MyCalMind.

`--mac` / `--ios` / `--android` select a subset; no flag builds all three.
Two rules the header states because both were proven the hard way: never run
two heavy build/device processes at once on this machine — a flaky WebKit
test under load and an Android emulator crash when gradle and xcodebuild
overlapped have both actually happened, so serialize. And Xcode's
`derivedDataPath` for these builds prefers `/Volumes/SPACE` when that scratch
volume is mounted, while gradle's own cache deliberately stays on the
internal disk — `/Volumes/SPACE` is exFAT and does not support the atomic
directory/classpath writes gradle's cache needs (proven by a failed build
against it).

## Traps

- **canon/packages/core/tsconfig.json extends `../../tsconfig.base.json`** —
  which is why canon/tsconfig.base.json exists and is itself an exact-mode
  entry. Delete it and both the typecheck and the vitest transform fail in
  ways that name neither file.
- **The two server-protocol tests are excluded from the canon run**
  (vitest.canon.config.mts): canon carries CalMind's copies, which read the
  server out of CalMind's own tree. They still run in CalMind and ChefMind;
  the exclusion here loses nothing that was ever covered here.
- **vitest.canon.config.mts lives OUTSIDE canon/ deliberately** — canon
  holds only bytes some consumer carries, and no consumer has this config.
- **The check's default parent is the sibling directory.** Working from a
  checkout somewhere else, set MIND_DIR or the check silently skips every
  consumer — it says so per repo, so read the output, not just the exit code.
