#!/bin/sh
# Deploy CORE — that is, propagate canon into the consumer repos.
#
# CoreMind ships to no server and no store. Its platforms ARE the four app
# repos, so "deploying core" means putting the canonical bytes where the
# consumers carry them, and then proving the apps still pass with them.
#
#   sh bin/deploy-core.sh                  fix DRIFT in every consumer
#   sh bin/deploy-core.sh --only CalMind   just that one
#   sh bin/deploy-core.sh --copy-down      …and land the `owed` lags too
#   sh bin/deploy-core.sh --dry-run        say what would be written
#
# WHAT IT WILL AND WILL NOT WRITE, because a tool that copies files over an
# app's source has to be exact about its own reach:
#   exact  the consumer is supposed to be byte-identical. If it is not, that
#          is drift, and canon wins. Written by default.
#   owed   a verified lag: canon is ahead and the copy-down is owed. NOT
#          written by default — landing one changes what an app does, so it
#          is opt-in (--copy-down) and reported either way. A row whose note
#          says BLOCKED is refused even then, by name.
#   fork   a deliberate divergence. Never written, under any flag.
#
# Every repo it touches must be CLEAN first — this overwrites tracked source,
# and doing that on top of someone's uncommitted work would mix two changes
# into one diff with no way back. It stages nothing and commits nothing: the
# copy is left in the working tree for a person to read.
set -e
cd "$(dirname "$0")/.."
PARENT="${MIND_DIR:-$(cd .. && pwd)}"

DRY=0; COPYDOWN=0; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY=1 ;;
    --copy-down) COPYDOWN=1 ;;
    --only)
      # `shift` without a value took the NEXT FLAG as the name (--only
      # --dry-run swallowed the dry run) or, at the end of argv, shifted past
      # the end and killed the script with nothing said.
      case "${2:-}" in
        ''|-*) echo "--only needs a consumer name" >&2; exit 1 ;;
      esac
      ONLY="$2"; shift ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -n "$ONLY" ] && [ ! -f "consumers/$ONLY.tsv" ]; then
  echo "no manifest for '$ONLY' — consumers/ holds: $(ls consumers/*.tsv | xargs -n1 basename | sed 's/\.tsv$//' | tr '\n' ' ')" >&2
  exit 1
fi

WROTE=0; TOUCHED=""; BLOCKED=0; CHECKED=0
for TSV in consumers/*.tsv; do
  NAME=$(basename "$TSV" .tsv)
  [ -z "$ONLY" ] || [ "$ONLY" = "$NAME" ] || continue
  ROOT="$PARENT/$NAME"
  if [ ! -d "$ROOT" ]; then
    echo "== $NAME — no checkout at $ROOT, skipped"
    continue
  fi
  CHECKED=$((CHECKED + 1))
  echo "== $NAME ($ROOT)"

  # Clean tree, or nothing. Checked per repo, before that repo is written to,
  # and checked on a DRY RUN too — a rehearsal that prints a write plan for a
  # repo the real run will refuse is a rehearsal of the wrong thing.
  #
  # The status is captured with its EXIT CODE. `[ -n "$(git status ...)" ]`
  # reads empty output as "clean", and git prints nothing to stdout when it
  # fails — not a repository, a broken index, no permission — so the check
  # failed OPEN and the script went on to overwrite source.
  if ST=$(git -C "$ROOT" status --porcelain --untracked-files=no 2>&1); then
    if [ -n "$ST" ]; then
      echo "  refusing: $NAME has uncommitted tracked changes — this writes over source" >&2
      printf '%s\n' "$ST" | sed 's/^/    /' >&2
      [ "$DRY" = 0 ] && exit 1
      echo "  (dry run: continuing, but the real run stops here)" >&2
    fi
  else
    echo "  refusing: cannot read $NAME's git status — not overwriting source blind" >&2
    printf '%s\n' "$ST" | sed 's/^/    /' >&2
    exit 1
  fi

  n=0; behind=0
  while IFS="$(printf '\t')" read -r MODE CANON LOCAL NOTE || [ -n "$MODE" ]; do
    case "$MODE" in ''|'#'*) continue ;; esac
    [ -f "$CANON" ] || { echo "  canon file missing: $CANON" >&2; exit 1; }
    # A missing local file is an error for `exact` and `fork` — the manifest
    # says this repo CARRIES it, and a manifest that overstates what is shared
    # is worse than none. For `owed` it is the ordinary case of a copy-down
    # that ADDS a file the consumer never had (MyCalMind gaining RichText.tsx
    # so Notes.tsx can land): the row's whole point is that it is not there yet.
    if [ ! -f "$ROOT/$LOCAL" ]; then
      if [ "$MODE" != "owed" ]; then
        echo "  $NAME no longer carries $LOCAL" >&2; exit 1
      fi
    elif cmp -s "$CANON" "$ROOT/$LOCAL"; then
      continue   # already agrees
    fi

    case "$MODE" in
      fork) continue ;;
      exact)
        printf '  drift  %s\n' "$LOCAL" ;;
      owed)
        case "$NOTE" in
          *BLOCKED*)
            printf '  \033[33m○\033[0m owed, BLOCKED: %s — %s\n' "$LOCAL" "$NOTE"
            BLOCKED=$((BLOCKED + 1)); behind=$((behind + 1)); continue ;;
        esac
        if [ "$COPYDOWN" = 0 ]; then
          printf '  \033[33m○\033[0m owed (--copy-down to land it): %s\n' "$LOCAL"
          behind=$((behind + 1)); continue
        fi
        printf '  copy   %s — %s\n' "$LOCAL" "$NOTE" ;;
      *) echo "  unknown mode '$MODE' for $LOCAL" >&2; exit 1 ;;
    esac

    if [ "$DRY" = 0 ]; then
      mkdir -p "$(dirname "$ROOT/$LOCAL")"
      cp "$CANON" "$ROOT/$LOCAL"
      # Prove the copy landed rather than trusting cp's exit status.
      cmp -s "$CANON" "$ROOT/$LOCAL" || { echo "  the copy of $LOCAL did not take" >&2; exit 1; }
    fi
    n=$((n + 1)); WROTE=$((WROTE + 1))
  done < "$TSV"

  if [ "$n" -gt 0 ]; then
    case " $TOUCHED " in *" $NAME "*) ;; *) TOUCHED="$TOUCHED $NAME" ;; esac
    printf '  %d file(s) %s\n' "$n" "$([ "$DRY" = 1 ] && echo 'would be written' || echo written)"
  elif [ "$behind" -gt 0 ]; then
    # NOT "already carries canon". It carries canon everywhere the manifest
    # calls for it today, and is knowingly behind on $behind file(s) — saying
    # the first and leaving out the second read as a contradiction of the
    # lines directly above it.
    printf '  \033[32m✓\033[0m no drift; %d owed file(s) left as they are\n' "$behind"
  else
    printf '  \033[32m✓\033[0m already carries canon\n'
  fi
done

if [ "$CHECKED" -eq 0 ]; then
  echo "no consumer checkout was found under $PARENT — nothing was done" >&2
  exit 1
fi

# ------------------------------------------------------------------ the proof
# A copy that compiles and passes is a copy that landed. Running each touched
# app's OWN suite is the only thing that can say so — canon's suite passing
# here says nothing about an app whose screens import these modules.
if [ "$DRY" = 0 ] && [ -n "$TOUCHED" ]; then
  for NAME in $TOUCHED; do
    ROOT="$PARENT/$NAME"
    echo ""
    echo "==> proving $NAME with its own suite"
    # An UNPROVEN copy is a failure, not a pass. Every reason the proof cannot
    # run ends this script non-zero, because bin/deploy.sh cascades production
    # deploys off its exit status: "we could not check" must never reach that
    # as "we checked".
    if [ ! -d "$ROOT/node_modules" ]; then
      echo "$NAME has no node_modules, so the copy cannot be proven." >&2
      echo "  Run \`npm install\` there and re-run; the files are already written." >&2
      exit 1
    fi
    # Named explicitly rather than trusted: `npm run typecheck` in a repo with
    # no such script exits 1 saying "Missing script", which this would have
    # reported as a FAILED TYPECHECK — blaming a check that never ran.
    if ! ( cd "$ROOT" && npm run -s typecheck --silent >/dev/null 2>&1 ) \
       && ! node -e "process.exit((require('$ROOT/package.json').scripts||{}).typecheck?0:1)"; then
      echo "$NAME defines no \`typecheck\` script — the copy cannot be proven the usual way." >&2
      exit 1
    fi
    LOG=$(mktemp -t coremind-proof)
    if ! ( cd "$ROOT" && npm run -s typecheck ) >"$LOG" 2>&1; then
      echo "$NAME's typecheck FAILED with canon in place — look before committing:" >&2
      tail -25 "$LOG" >&2; echo "full output: $LOG" >&2; exit 1
    fi
    if ! ( cd "$ROOT" && npm run -s test:core -- --reporter=dot ) >"$LOG" 2>&1; then
      # Its output is KEPT. Discarding it left "the core suite failed" as the
      # whole report, with the consumer's source already overwritten and no
      # way to tell a real regression from a harness problem.
      echo "$NAME's core suite FAILED with canon in place — look before committing:" >&2
      grep -E '✕|×|FAIL|Error|Tests ' "$LOG" | tail -20 >&2; echo "full output: $LOG" >&2; exit 1
    fi
    rm -f "$LOG"
    echo "    typecheck and core suite green"
  done
fi

echo ""
echo "────────────────────────────────"
if [ "$DRY" = 1 ]; then
  echo "dry run: $WROTE file(s) would be written${TOUCHED:+ in$TOUCHED}"
else
  echo "$WROTE file(s) written${TOUCHED:+ in$TOUCHED}"
  [ "$WROTE" -eq 0 ] || echo "left uncommitted on purpose — read the diff, then commit it in each repo"
fi
[ "$BLOCKED" -eq 0 ] || echo "$BLOCKED owed row(s) BLOCKED — see the notes above; they need a person"

# A marker for bin/deploy.sh, which cascades to the consumers only when core
# actually changed something under them. Machine-readable on purpose — grepping
# prose is how a cascade ends up firing on a run that wrote nothing — and
# printed ONLY when asked for, so a person running this directly does not get a
# line of protocol at the end of their output.
[ -z "${CORE_MARKER:-}" ] || echo "CORE_WROTE=$WROTE"
