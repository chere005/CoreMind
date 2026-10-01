#!/bin/sh
# Deploy the suite — one target, or all of it, with DOWNSTREAM CASCADE.
#
#   sh bin/deploy.sh all                 core, then every app, in order
#   sh bin/deploy.sh core                core — and then everything that carries it
#   sh bin/deploy.sh CalMind             CalMind — and then ChefMind, which needs it
#   sh bin/deploy.sh --only ChefMind     ChefMind alone, cascade suppressed
#   sh bin/deploy.sh all --dry-run       every step, writing nothing
#   sh bin/deploy.sh all --plan          resolve the order and stop
#
# THE GRAPH — its edges, and why each one is real rather than tidy — lives in
# bin/plan.sh, which this script and bin/dtp.sh both source.
#
# Flags: --quick (the fast gates where an app has them) · --dry-run
#        --only <target> (no cascade) · --copy-down (core: land the owed lags)
#        --with-devices (include MyCalMind, which needs a phone plugged in)
set -e
cd "$(dirname "$0")/.."
PARENT="${MIND_DIR:-$(cd .. && pwd)}"
. bin/plan.sh

QUICK=""; DRY=0; ONLY=0; COPYDOWN=""; DEVICES=0; PLANONLY=0; WANT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --quick)        QUICK="--quick" ;;
    --dry-run)      DRY=1 ;;
    # --plan resolves the cascade and stops. --dry-run still RUNS every app's
    # deploy script (in its own dry mode), which costs a full export and gate
    # run per app; this is for reading the order back.
    --plan)         PLANONLY=1 ;;
    --only)         ONLY=1 ;;
    --copy-down)    COPYDOWN="--copy-down" ;;
    --with-devices) DEVICES=1 ;;
    -*)             echo "unknown flag: $1" >&2; exit 1 ;;
    all)            WANT="$ORDER"; DEVICES=1 ;;
    *)              WANT="$WANT $1" ;;
  esac
  shift
done
resolve_plan

echo "==> plan:$PLAN"
[ "$ONLY" = 1 ] && echo "    (--only: downstream cascade suppressed)"
case " $PLAN " in
  *" MyCalMind "*) echo "    (MyCalMind installs onto a connected iPhone — it needs one plugged in)" ;;
esac
[ "$PLANONLY" = 0 ] || exit 0
echo ""

repo_at() {
  R="$PARENT/$1"
  [ -d "$R" ] || { echo "no checkout at $R" >&2; exit 1; }
  echo "$R"
}

DRYFLAG=""
[ "$DRY" = 1 ] && DRYFLAG="--dry-run"

CORE_CASCADE=1; SHIPPED=""; SKIPPED=""
for T in $PLAN; do
  # THE GATE the header promises: "the cascade fires only when core actually
  # wrote something". It was computed and printed and never consulted, so an
  # in-sync `deploy.sh core` shipped three apps to production while saying
  # nothing had propagated.
  #
  # It drops only what came in BY CASCADE. A target the operator named — and
  # `all` names every one of them — ships on its own merit, which is what
  # they asked for.
  if [ "$CORE_CASCADE" = 0 ] && [ "$T" != "core" ]; then
    case " $WANT " in
      *" $T "*) ;;
      *) echo "──────────────────────────────── $T"
         echo "    skipped: here only because core is, and core propagated nothing"
         echo ""
         SKIPPED="$SKIPPED $T"
         continue ;;
    esac
  fi
  echo "──────────────────────────────── $T"
  case "$T" in
    core)
      OUT=$(CORE_MARKER=1 sh bin/deploy-core.sh $DRYFLAG $COPYDOWN 2>&1) || { echo "$OUT" >&2; exit 1; }
      echo "$OUT" | grep -v '^CORE_WROTE='
      WROTE=$(echo "$OUT" | sed -n 's/^CORE_WROTE=//p')
      # A propagation that wrote nothing leaves every consumer exactly as it
      # was, so the apps that follow are here on their own merit or not at all.
      if [ "${WROTE:-0}" = "0" ]; then
        CORE_CASCADE=0
        echo "    core wrote nothing — anything here ONLY because core is, drops out"
      fi
      ;;
    CalMind)
      R=$(repo_at CalMind)
      ( cd "$R" && ./server/deploy.sh prod test --yes-prod $QUICK $DRYFLAG )
      ;;
    ChefMind)
      R=$(repo_at ChefMind)
      # --yes-prod even on a dry run: the flag is the consent, and the script
      # refuses a bare run. --dry-run is what makes it write nothing.
      ( cd "$R" && ./deploy.sh --yes-prod $DRYFLAG )
      ;;
    AcctMind)
      R=$(repo_at AcctMind)
      ( cd "$R" && ./deploy.sh $QUICK $DRYFLAG )
      ;;
    MyCalMind)
      R=$(repo_at MyCalMind)
      ( cd "$R" && sh tools/deploy-device.sh $DRYFLAG )
      ;;
    WriteMind)
      R=$(repo_at WriteMind)
      # The Release .app, smoked and installed at /Applications — there is no
      # server and no store, so that IS the deploy. --quick is accepted there
      # and does nothing: it has no fast gate to skip.
      ( cd "$R" && sh tools/deploy.sh $QUICK $DRYFLAG )
      ;;
  esac
  SHIPPED="$SHIPPED $T"
  echo ""
done

echo "────────────────────────────────"
# What RAN, not what was planned. The old ending named the whole plan even
# when the cascade gate had dropped most of it — a summary that reads as three
# production deploys that did not happen.
if [ "$DRY" = 1 ]; then
  echo "dry run complete:${SHIPPED:- nothing}"
else
  echo "deployed:${SHIPPED:- nothing}"
fi
[ -z "$SKIPPED" ] || echo "skipped (core propagated nothing, and these were here only for it):$SKIPPED"
