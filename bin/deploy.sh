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
# THE GRAPH, and why each edge is real rather than tidy:
#
#   core ──▶ CalMind, ChefMind, MyCalMind, AcctMind
#       Canon IS those repos' source. Change it and their builds change, so
#       shipping core without shipping them means the canonical bytes are
#       live nowhere. The cascade fires only when core actually wrote
#       something — a no-op propagation redeploys nothing.
#
#   CalMind ──▶ ChefMind
#       ChefMind has no server. It syncs through CalMind's API in the `chef`
#       space, and its own deploy REFUSES to ship unless the live API reports
#       that space. So CalMind's server must land first; ChefMind following
#       it automatically is the whole reason this ordering is in a script
#       instead of in somebody's memory.
#
# Nothing else has an edge: AcctMind is independent, and MyCalMind talks to
# no server at all.
#
# Flags: --quick (the fast gates where an app has them) · --dry-run
#        --only <target> (no cascade) · --copy-down (core: land the owed lags)
#        --with-devices (include MyCalMind, which needs a phone plugged in)
set -e
cd "$(dirname "$0")/.."
PARENT="${MIND_DIR:-$(cd .. && pwd)}"

# Deployment order for the whole suite. Every run is a subset of this list, in
# this sequence — so a cascade can never reorder itself into shipping ChefMind
# before the API it checks.
ORDER="core CalMind ChefMind AcctMind MyCalMind"

downstream_of() {
  case "$1" in
    core)    echo "CalMind ChefMind AcctMind MyCalMind" ;;
    CalMind) echo "ChefMind" ;;
    *)       echo "" ;;
  esac
}

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
[ -n "$WANT" ] || { echo "name a target: all, core, CalMind, ChefMind, AcctMind, MyCalMind" >&2; exit 1; }

for T in $WANT; do
  case " $ORDER " in
    *" $T "*) ;;
    *) echo "unknown target '$T' — one of: $ORDER" >&2; exit 1 ;;
  esac
done

# ------------------------------------------------------------- the closure
# --only suppresses the cascade; otherwise every target drags its downstream
# in. Resolved BEFORE anything ships, so the plan can be printed and read.
SET="$WANT"
if [ "$ONLY" = 0 ]; then
  # One pass per node in dependency order is enough for a graph two deep, and
  # a fixed number of passes cannot loop for ever if an edge is ever added.
  for _ in 1 2 3; do
    for T in $SET; do
      for D in $(downstream_of "$T"); do
        case " $SET " in *" $D "*) ;; *) SET="$SET $D" ;; esac
      done
    done
  done
fi

PLAN=""
for T in $ORDER; do
  case " $SET " in *" $T "*) ;; *) continue ;; esac
  # MyCalMind installs onto a phone, so it cannot ride an unattended cascade —
  # it is left out unless it was NAMED, or --with-devices (which `all` implies)
  # said so. Naming a target IS the consent; only the cascade needs the flag.
  if [ "$T" = "MyCalMind" ] && [ "$DEVICES" = 0 ]; then
    case " $WANT " in
      *" MyCalMind "*) ;;
      *) continue ;;
    esac
  fi
  PLAN="$PLAN $T"
done
[ -n "$PLAN" ] || { echo "nothing to do" >&2; exit 1; }

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

CORE_CASCADE=1
for T in $PLAN; do
  echo "──────────────────────────────── $T"
  case "$T" in
    core)
      OUT=$(sh bin/deploy-core.sh $DRYFLAG $COPYDOWN 2>&1) || { echo "$OUT" >&2; exit 1; }
      echo "$OUT" | grep -v '^CORE_WROTE='
      WROTE=$(echo "$OUT" | sed -n 's/^CORE_WROTE=//p')
      # A propagation that wrote nothing leaves every consumer exactly as it
      # was, so the apps that follow are here on their own merit or not at all.
      if [ "${WROTE:-0}" = "0" ]; then
        CORE_CASCADE=0
        echo "    core wrote nothing — the apps below are unchanged BY CORE"
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
  esac
  echo ""
done

echo "────────────────────────────────"
if [ "$DRY" = 1 ]; then
  echo "dry run complete:$PLAN"
else
  echo "deployed:$PLAN"
fi
[ "$CORE_CASCADE" = 1 ] || echo "(core propagated nothing this run)"
