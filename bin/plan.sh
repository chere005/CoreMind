# The suite's release graph — SOURCED, never run. bin/deploy.sh and bin/dtp.sh
# both read it (`. bin/plan.sh`, before their flag loops, because `all` reads
# $ORDER there), so the order a deploy and a dtp ship in cannot disagree. It
# used to be two identical copies held together by a same-commit rule.
#
# The caller sets WANT, ONLY and DEVICES from its flags, then calls
# resolve_plan, which sets PLAN — or exits 1 saying why.
#
# THE GRAPH, and why each edge is real rather than tidy:
#
#   core ──▶ CalMind, ChefMind, MyCalMind, AcctMind
#       Canon IS those repos' source. Change it and their builds change, so
#       shipping core without shipping them means the canonical bytes are
#       live nowhere. bin/deploy.sh fires this cascade only when core
#       actually wrote something; bin/dtp.sh always ships it, because its
#       core lane refuses a propagation that wrote anything.
#
#   CalMind ──▶ ChefMind
#       ChefMind has no server. It syncs through CalMind's API in the `chef`
#       space, and its own deploy REFUSES to ship unless the live API reports
#       that space. So CalMind's server must land first; ChefMind following
#       it automatically is the whole reason this ordering is in a script
#       instead of in somebody's memory.
#
# Nothing else has an edge: AcctMind is independent, MyCalMind talks to no
# server at all, and WriteMind (2026-09-18) is a native macOS app that
# carries no canon — its deploy is its Mac bundle, installed locally.

# Deployment order for the whole suite. Every run is a subset of this list, in
# this sequence — so a cascade can never reorder itself into shipping ChefMind
# before the API it checks.
ORDER="core CalMind ChefMind AcctMind MyCalMind WriteMind"

downstream_of() {
  case "$1" in
    core)    echo "CalMind ChefMind AcctMind MyCalMind" ;;
    CalMind) echo "ChefMind" ;;
    *)       echo "" ;;
  esac
}

resolve_plan() {
  [ -n "$WANT" ] || { echo "name a target: all, core, CalMind, ChefMind, AcctMind, MyCalMind, WriteMind" >&2; exit 1; }

  for T in $WANT; do
    case " $ORDER " in
      *" $T "*) ;;
      *) echo "unknown target '$T' — one of: $ORDER" >&2; exit 1 ;;
    esac
  done

  # ----------------------------------------------------------- the closure
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
}
