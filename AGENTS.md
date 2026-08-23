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
  suite, plus each app's own macOS/iOS/Android builds — the flag is passed
  through to its lane, see Platforms). Core's own lane bumps its minor version
  only on a tag collision, otherwise it tags whatever `package.json` says.
- **The suite's status reporter is this repo's.** `bin/report-status.sh` is
  what the baseline's "a status failure never fails a release" rule is about:
  every failure path in it warns on stderr and exits 0, deliberately, and
  `start` prints its run id even when the push failed because the caller still
  has a `finish` to make. `bin/dtp.sh` calls it at five points — the start, a
  beat every minute while a lane is in flight, and three finishes (failed,
  shipped-with-a-platform-build-down, clean) — and exports `MIND_RUN_ID` so a
  batch draws ONE card. Sean, 2026-08-23: "there should be one card per tdtp if
  multiple jobs are triggered in one batch". Every app ships itself now and
  each lane would otherwise open a run of its own, so the parent's id travels
  down; a lane that sees it reports nothing and lets the parent's card stand.
- **A lane's non-zero exit means "shipped, a build is owed" — not "stopped".**
  A self-shipping lane ends non-zero when a device build did not finish, so
  "it all worked" cannot be read off its exit status. Under `set -e` that would
  abort the batch at the first unplugged phone and stop every repo after it
  from shipping at all, which is a far worse answer than the one the exit code
  is trying to give. `bin/dtp.sh` catches it: the verdict is folded into
  `PLATFORM_BAD`, the run continues, and this script ends non-zero itself at
  the finish. A lane that failed BEFORE its tag still stops everything — the
  TAG is the evidence for which happened, never the exit code.
- **`deploy-core.sh` writes over app source and commits nothing.** It refuses
  a dirty consumer (two changes in one diff has no way back), never touches a
  `fork` row, leaves `owed` rows alone unless asked, refuses the BLOCKED one
  by name, and runs each touched app's own typecheck and core suite before
  claiming the copy landed.
- **A live send is a host's config change, never a canon edit.** Canon's mail
  transport (`canon/server/lib/mail.php`) stays commented out beside the stub.

## Platforms

CoreMind ships nothing of its own — no server, no app, no platform build; it
tags itself and stops.

**Platform builds belong to the app, not to this repo.** All four now carry
their own `tools/build-platforms.sh`, grown the same day on Sean's word —
2026-08-23, "all apps should have a deploy on their own mechanism inside their
repo... coremind is to ship all apps simultaneously". So `bin/dtp.sh` DETECTS
that file rather than listing apps: an app that has it gets `--platforms`
passed THROUGH to its own lane (and `--web`, meaning the release with no
platform builds, when the flag is unset), and whatever it builds is credited to
it. What CoreMind owns here is the ORDER and that pass-through — the artifacts
are the app's, built where the app's lane wants them: its desktop bundle before
its tag, its device builds after its push.

`bin/build-platforms.sh` is therefore the **fallback**, run only for an app
with no `tools/build-platforms.sh` of its own — today, none of the four. It is
also the ORIGIN those four copies came down from, comments and all (they say
so in their own headers), which is why it stays complete rather than trimmed to
whoever still needs it. Its table is what the three lists below describe — not
what a `dtp --platforms` run executes today:

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
  script has to run again. It does — from here, and from the verbatim copy at
  MyCalMind's `tools/patch-rndeps-catalyst.js`, which is the one that actually
  runs now. The thing to know is that nothing upstream has been fixed.
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

`--mac` / `--ios` / `--android` select a subset, `--dry-run` prints the plan
and stops, and no flag at all builds all three — the same convention all four
copies use, so a gesture learned here works in any of them.
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
