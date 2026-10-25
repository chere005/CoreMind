# Working in CoreMind

The baseline for all of Sean's repos lives in ~/GIT/AgentSuite/AGENTS.md
and is imported here; this file holds only what is true of THIS repo.
@../AgentSuite/AGENTS.md

## Rules

- **Never a dependency.** No app imports, links or installs this repo; the suite clones and checks. Changing that starts in the consumers' AGENTS.md, on Sean's word.
- **Canon changes are copies, not edits.** Fix lands in its home repo (CalMind unless a superset lives elsewhere), then the SAME BYTES are copied here and to every mirroring consumer; promoting a verified superset is also a copy.
- **Manifests are hand-kept.** `consumers/*.tsv` rows are mode/canon/local/note, tab-separated: `exact` fails the check on drift; `owed` = verified lag awaiting copy-down (promote to `exact` on landing); `fork` = deliberate divergence, note says why. Never demote a failing `exact` to `fork` to go green.
- **The deploy graph lives only in `bin/plan.sh`** (`ORDER`, `downstream_of()`, `resolve_plan`); `bin/deploy.sh` and `bin/dtp.sh` source it before reading flags; a new edge goes there. Deploys CASCADE; `--only` ships one thing.
- **`npm run dtp` / `tdtp` wrap `bin/dtp.sh`**, the suite orchestrator (not a per-repo release script). No default target: pass one after `--`. tdtp (`--full`) runs each repo's tests first. Core's lane bumps its minor only on a tag collision, else tags what `package.json` says.
- **`bin/report-status.sh` is this repo's.** Every failure path warns on stderr and exits 0; `start` prints its run id even if the push failed (caller still owes a `finish`).
  `bin/dtp.sh` calls it at five points (start, a beat each minute, three finishes: failed / shipped-with-platform-build-down / clean) and exports `MIND_RUN_ID`; a lane that sees it reports nothing.
- **A lane's non-zero exit means "shipped, a build is owed", not "stopped".** `bin/dtp.sh` folds it into `PLATFORM_BAD`, continues, and ends non-zero itself at the finish.
- **The TAG is the evidence, never the exit code:** a tag the lane itself made, absent before it ran. HEAD still carrying the PREVIOUS release's tag proves nothing. A lane that failed BEFORE its tag stops everything; so does one killed by a signal (exit >128), whatever its tags say; ^C/TERM at the batch ends it, card closed once, dying of that signal.
- **`deploy-core.sh` writes app source, commits nothing:** refuses a dirty consumer, never touches `fork` rows, leaves `owed` alone unless asked, refuses the BLOCKED row by name, runs each touched app's typecheck and core suite before claiming the copy landed.
- **A live mail send is a host's config change, never a canon edit.** CalMind's `server/lib/mail.php` transport stays commented out beside the stub.

## Commands

Before committing run all: `npm test` (canon suite), `npm run typecheck`, `npm run check` (against sibling checkouts).

```
npm run dtp -- --only core        # CoreMind alone: propagate canon, bin/check-drift.sh, tag, push
npm run dtp -- all                # every repo, core first
npm run tdtp -- all --platforms   # test-first, whole suite, plus each app's macOS/iOS/Android builds
sh bin/check-heavy-lock.sh        # also required after any change to canon/tools/heavy-lock.sh
sh bin/check-plan.sh              # the release order and the .private-targets extension (seconds)
```

- A bare `core` cascades into CalMind, ChefMind, AcctMind. `check-heavy-lock.sh` stays out of `npm test` (waits ~2 min; core lane runs `npm test` every tdtp).

## Platforms

CoreMind ships nothing of its own; it tags itself and stops. Platform builds belong to the app.

- Each app carries `tools/build-platforms.sh`; `bin/dtp.sh` DETECTS it and passes `--platforms` through (`--web` = release with no platform builds, when unset). CoreMind owns the ORDER and the pass-through only. Private targets ride along: name them, one per line, in the untracked, gitignored `.private-targets` at the checkout root (default none, per machine); `bin/plan.sh` appends them last and `bin/deploy.sh`/`bin/dtp.sh` run their own `tools/` lane, taking `--web` as a no-op.
- `bin/build-platforms.sh` is the **fallback**, run only for an app with no script of its own (today none) and the ORIGIN of the copies; keep it complete. Flags: `--mac`/`--ios`/`--android` subset, `--dry-run` plan only, none = all three.
- **macOS:** Tauri bundle for CalMind, ChefMind, AcctMind; Mac Catalyst app for MyCalMind (no Tauri). Copied into `/Applications` and verified.
- **Catalyst:** MyCalMind's `withMacCatalyst` plugin plus the script cover: widget target needs `SUPPORTS_MACCATALYST`; arm64 only (no x86_64 slice); builds from source (`EXPO_USE_PRECOMPILED_MODULES=0 RCT_USE_PREBUILT_RNCORE=0`); vendored ReactNativeDependencies malformed for that slice.
- **RNDeps repair not durable:** `[CP-User] [RNDeps]` phase is `alwaysOutOfDate`, re-extracts the pristine bundle mid-build → repair is PATCHED INTO that phase by `bin/patch-rndeps-catalyst.js` (idempotent; the copy that runs is MyCalMind's `tools/patch-rndeps-catalyst.js`). `expo prebuild` rewrites the pbxproj → rerun.
- **Android:** build, install, launch on local emulator or hardware for CalMind, ChefMind, AcctMind, MyCalMind.
- **iOS:** builds once, installs via `devicectl` to every phone the app belongs on: CalMind to Sean's, Autumn's, Patricia's; ChefMind to Sean's and Autumn's; AcctMind to Sean's; nothing else on Autumn's or Patricia's.
  Off phone: skipped with a note; refusing phone: warned; fails only if NONE took it. CalMind also installs its watch companion when a paired Watch is reachable.
- **No per-phone app cap:** team 2LGYTL3FSJ ("Sean Cheren") is PAID (`TimeToLive 365`); notes about freeing a slot are obsolete.
- MyCalMind iOS is BUILD ONLY, never installs: its `tools/deploy-device.sh` owns its device deploy (two lanes on one phone disagree).
- **Heavy builds are serialized by a lock, not memory:** every platform block in `bin/build-platforms.sh` runs in `heavy_lock "<app> <platform>"` … `heavy_unlock` from `canon/tools/heavy-lock.sh` (each app carries it byte for byte as `tools/heavy-lock.sh`; adopting it in their build script is each app's change).
- Lock: `mkdir` at `/tmp/mind-heavy-<uid>.lock` (per machine user, outside repos; `$TMPDIR` is not shared).
- A waiter prints the holder (repo, step, pid, since) every 30 s, reports to the card via `MIND_PHASE_FILE`, fails after 30 min (`MIND_HEAVY_WAIT`). Dead/recycled holder pid is taken over; uncreatable lock or nested heavy block fails at once.
- Released on EXIT, INT, TERM via traps that WRAP the caller's. `check-heavy-lock.sh` uses its own scratch lock (`MIND_HEAVY_LOCK`, nothing else may set it).
- derivedData and gradle cache stay on the internal disk: `/Volumes/SPACE` is exFAT (no codesign xattrs, no atomic dir writes for gradle; see `BUILD_SCRATCH` note in `bin/build-platforms.sh`).

## Traps

- `canon/packages/core/tsconfig.json` extends `../../tsconfig.base.json` → that is why `canon/tsconfig.base.json` exists (exact-mode entry). Delete it → typecheck and vitest transform fail naming neither file.
- The two server-protocol tests are excluded from the canon run (`vitest.canon.config.mts`, which lives OUTSIDE `canon/` on purpose: canon holds only consumer-carried bytes): they read CalMind's tree; app.php half runs only in CalMind, ChefMind's fork copies assert protocol.json alone.
- The check's default parent is the sibling directory. Elsewhere, set `MIND_DIR` or the check silently skips every consumer (says so per repo; read the output, not the exit code).
