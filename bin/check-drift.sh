#!/bin/sh
# Does every consumer still carry the canon bytes it claims to?
#
#   sh bin/check-drift.sh                  every consumer with a checkout
#   sh bin/check-drift.sh CalMind ChefMind  just those
#
# Consumers are expected as SIBLINGS of this checkout (~/GIT/CalMind next to
# ~/GIT/CoreMind); MIND_DIR overrides the parent directory.
#
# The manifest rows (consumers/<Repo>.tsv) carry a MODE each:
#   exact  the consumer's copy must equal canon byte-for-byte. A mismatch is
#          DRIFT and fails this check — that is the entire point of the repo.
#   owed   a verified lag: canon is ahead and the copy-down is owed. Reported
#          loudly, does not fail — it is the work list, not an accident. When
#          the copy lands, the row is promoted to exact by hand.
#   fork   a deliberate divergence (the note says why). Reported, never failed.
#
# A missing file is a failure in any mode: the manifest says the repo carries
# it, and a manifest that overstates what is shared is worse than none.
set -e
cd "$(dirname "$0")/.."
PARENT="${MIND_DIR:-$(cd .. && pwd)}"

FAIL=0; DRIFT=0; OWED=0
for TSV in consumers/*.tsv; do
  NAME=$(basename "$TSV" .tsv)
  if [ $# -gt 0 ]; then
    case " $* " in *" $NAME "*) ;; *) continue ;; esac
  fi
  ROOT="$PARENT/$NAME"
  if [ ! -d "$ROOT" ]; then
    echo "== $NAME — no checkout at $ROOT, skipped"
    continue
  fi
  echo "== $NAME ($ROOT)"
  n_exact=0
  while IFS="$(printf '\t')" read -r MODE CANON LOCAL NOTE; do
    case "$MODE" in ''|'#'*) continue ;; esac
    if [ ! -f "$CANON" ]; then
      printf '  \033[31m✗\033[0m canon file missing: %s\n' "$CANON"; FAIL=$((FAIL+1)); continue
    fi
    if [ ! -f "$ROOT/$LOCAL" ]; then
      printf '  \033[31m✗\033[0m %s says it carries %s — the file is gone\n' "$NAME" "$LOCAL"
      FAIL=$((FAIL+1)); continue
    fi
    case "$MODE" in
      exact)
        if cmp -s "$CANON" "$ROOT/$LOCAL"; then
          n_exact=$((n_exact+1))
        else
          printf '  \033[31m✗\033[0m DRIFT: %s differs from %s\n' "$LOCAL" "$CANON"
          FAIL=$((FAIL+1)); DRIFT=$((DRIFT+1))
        fi ;;
      owed)
        if cmp -s "$CANON" "$ROOT/$LOCAL"; then
          printf '  \033[32m✓\033[0m owed copy LANDED: %s — promote its row to exact\n' "$LOCAL"
        else
          printf '  \033[33m○\033[0m owed: %s — %s\n' "$LOCAL" "${NOTE:-copy-down owed}"
          OWED=$((OWED+1))
        fi ;;
      fork)
        printf '  \033[36m∥\033[0m fork: %s — %s\n' "$LOCAL" "${NOTE:-deliberate}" ;;
      *)
        printf '  \033[31m✗\033[0m unknown mode "%s" for %s\n' "$MODE" "$LOCAL"; FAIL=$((FAIL+1)) ;;
    esac
  done < "$TSV"
  printf '  \033[32m✓\033[0m %d exact files match canon\n' "$n_exact"
done

echo
echo "────────────────────────────────"
echo "$DRIFT drifted, $OWED copies owed, $FAIL failures"
[ "$FAIL" -eq 0 ] || exit 1
