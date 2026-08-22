# Working in CoreMind

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
- **`main` is the branch.** Stage explicit paths — never `git add -A`.

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
