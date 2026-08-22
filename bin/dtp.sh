#!/bin/sh
# dtp the suite — deploy, tag, push, across every repo, in dependency order.
#
#   sh bin/dtp.sh all                every repo, core first
#   sh bin/dtp.sh CalMind            CalMind — and ChefMind, which depends on it
#   sh bin/dtp.sh --only AcctMind    that one alone
#   sh bin/dtp.sh all --plan         resolve the order and stop
#   sh bin/dtp.sh all --full         tdtp: the full test run in each lane
#   sh bin/dtp.sh all --platforms    …and build the platforms a release does
#                                    not ship by itself: the macOS bundle and
#                                    the iOS build on the connected phone
#
# Each repo's OWN lane does the work — tools/dtp.sh in the four apps, which
# already bump the minor version, refuse a dirty tree or a non-main branch,
# never tag around a failed deploy, and push atomically. This adds exactly two
# things: the ORDER (bin/deploy.sh's graph, same edges, same reasons) and the
# fact that stopping at a failure leaves everything after it unshipped rather
# than half-shipped in an order nobody chose.
#
# CORE's lane is different, because CoreMind ships to no server: it propagates
# canon into the consumers, proves the drift check is clean, then tags and
# pushes itself. A consumer left carrying non-canon bytes stops the run — the
# apps below it would otherwise be tagged as "the canon release" while not
# being it.
set -e
cd "$(dirname "$0")/.."
PARENT="${MIND_DIR:-$(cd .. && pwd)}"
ORDER="core CalMind ChefMind AcctMind MyCalMind"

downstream_of() {
  case "$1" in
    core)    echo "CalMind ChefMind AcctMind MyCalMind" ;;
    CalMind) echo "ChefMind" ;;
    *)       echo "" ;;
  esac
}

FULL=0; ONLY=0; PLANONLY=0; DEVICES=0; PLATFORMS=0; WANT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --full)         FULL=1 ;;
    --only)         ONLY=1 ;;
    --plan)         PLANONLY=1 ;;
    --with-devices) DEVICES=1 ;;
    --platforms)    PLATFORMS=1 ;;
    -*)             echo "unknown flag: $1" >&2; exit 1 ;;
    all)            WANT="$ORDER"; DEVICES=1 ;;
    *)              WANT="$WANT $1" ;;
  esac
  shift
done
[ -n "$WANT" ] || { echo "name a target: all, core, CalMind, ChefMind, AcctMind, MyCalMind" >&2; exit 1; }
for T in $WANT; do
  case " $ORDER " in *" $T "*) ;; *) echo "unknown target '$T' — one of: $ORDER" >&2; exit 1 ;; esac
done

SET="$WANT"
if [ "$ONLY" = 0 ]; then
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
  if [ "$T" = "MyCalMind" ] && [ "$DEVICES" = 0 ]; then
    case " $WANT " in *" MyCalMind "*) ;; *) continue ;; esac
  fi
  PLAN="$PLAN $T"
done
[ -n "$PLAN" ] || { echo "nothing to do" >&2; exit 1; }

LANE=dtp; [ "$FULL" = 0 ] || LANE=tdtp
echo "==> $LANE plan:$PLAN"
[ "$ONLY" = 1 ] && echo "    (--only: downstream cascade suppressed)"
case " $PLAN " in
  *" MyCalMind "*) echo "    (MyCalMind's deploy installs onto a connected iPhone)" ;;
esac

# ------------------------------------------------------- look before shipping
# Every repo in the plan is checked BEFORE the first one ships. A run that
# stops on repo three because repo three was on a branch has already tagged
# and pushed two releases, and those cannot be taken back.
echo ""
echo "==> pre-flight"
for T in $PLAN; do
  # `core` is THIS checkout — resolved from the script, not by guessing a
  # directory called CoreMind next door. Those can be two different repos, and
  # then the branch and clean checks pass on one while the tag lands on the
  # other.
  case "$T" in core) R="$(pwd)" ;; *) R="$PARENT/$T" ;; esac
  [ -d "$R" ] || { echo "  no checkout at $R" >&2; exit 1; }
  B=$(git -C "$R" rev-parse --abbrev-ref HEAD)
  [ "$B" = "main" ] || { echo "  $T is on branch '$B', not main" >&2; exit 1; }
  if [ -n "$(git -C "$R" status --porcelain --untracked-files=no)" ]; then
    echo "  $T has uncommitted tracked changes:" >&2
    git -C "$R" status --porcelain --untracked-files=no | sed 's/^/    /' >&2
    exit 1
  fi
  git -C "$R" remote get-url origin >/dev/null 2>&1 \
    || { echo "  $T has no origin remote — the lane ends in a push" >&2; exit 1; }
  printf '  \033[32m✓\033[0m %-10s main, clean, has an origin\n' "$T"
done

# THE PRECONDITION THIS RUN ACTUALLY FAILS ON. MyCalMind installs onto a
# phone; without one its lane refuses — and being last, it refuses AFTER the
# earlier repos have deployed to production, tagged and pushed. Those do not
# come back, so the question gets asked here instead, while nothing has moved.
case " $PLAN " in
  *" MyCalMind "*)
    DEVJSON=$(mktemp -t coremind-devices)
    if xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null 2>&1; then
      N=$(python3 - "$DEVJSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
n = sum(1 for x in d.get('result', {}).get('devices', [])
        if x.get('hardwareProperties', {}).get('platform') == 'iOS'
        and x.get('connectionProperties', {}).get('tunnelState') in ('connected', 'available'))
print(n)
PY
)
    else
      N=0
    fi
    rm -f "$DEVJSON"
    if [ "${N:-0}" -lt 1 ]; then
      echo "  refusing: MyCalMind is in the plan and no iPhone is reachable." >&2
      echo "  It deploys LAST, so it would refuse after the others had already" >&2
      echo "  shipped, tagged and pushed. Plug one in, or leave it out:" >&2
      echo "    sh bin/dtp.sh core          (cascades to the three web apps)" >&2
      exit 1
    fi
    printf '  \033[32m✓\033[0m %-10s %s reachable iPhone(s)\n' "MyCalMind" "$N"
    ;;
esac
[ "$PLANONLY" = 0 ] || exit 0

PLATFORM_OK=""; PLATFORM_BAD=""
for T in $PLAN; do
  echo ""
  echo "──────────────────────────────── $LANE $T"
  case "$T" in
    core)
      # tdtp means the tests run. Without this the core lane tagged and pushed
      # a canon release having executed nothing — in the steady state the
      # pre-flight insists on, propagation writes no files and therefore
      # proves no consumer either.
      if [ "$FULL" = 1 ]; then
        echo "==> CoreMind's own suite"
        npm test
        npm run -s typecheck
      fi
      # Propagate, then hold the whole suite to it.
      sh bin/deploy-core.sh
      if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "CoreMind itself is dirty after propagating — look" >&2; exit 1
      fi
      for C in CalMind ChefMind AcctMind MyCalMind; do
        [ -d "$PARENT/$C" ] || continue
        if [ -n "$(git -C "$PARENT/$C" status --porcelain --untracked-files=no)" ]; then
          echo "" >&2
          echo "$C changed when canon was propagated — it was carrying drift." >&2
          echo "Read and commit that in $C first; a release tagged now would" >&2
          echo "name a tree that had not been reviewed." >&2
          git -C "$PARENT/$C" status --porcelain --untracked-files=no | sed 's/^/  /' >&2
          exit 1
        fi
      done
      sh bin/check-drift.sh
      VER=$(node -p "require('./package.json').version")
      if git rev-parse -q --verify "refs/tags/$VER" >/dev/null; then
        NEW=$(echo "$VER" | awk -F. '{printf "%d.%d.0", $1, $2+1}')
        perl -i -pe "s|\"version\": \"\Q$VER\E\"|\"version\": \"$NEW\"|" package.json
        grep -q "\"version\": \"$NEW\"" package.json \
          || { echo "guard: package.json does not carry $NEW" >&2; exit 1; }
        git add package.json && git commit -q -m "CoreMind $NEW"
        VER="$NEW"
      fi
      git tag -a "$VER" -m "CoreMind $VER"
      if ! git push --atomic --follow-tags origin main; then
        git tag -d "$VER" >/dev/null
        echo "CoreMind's push was rejected — nothing tagged. Pull and re-run." >&2
        exit 1
      fi
      echo "==> CoreMind $VER tagged and pushed"
      ;;
    *)
      R="$PARENT/$T"
      if [ "$FULL" = 1 ]; then ( cd "$R" && sh tools/tdtp.sh ); else ( cd "$R" && sh tools/dtp.sh ); fi
      # THE PLATFORMS THE RELEASE DID NOT SHIP. Run AFTER the lane, and its
      # failure is reported rather than fatal: by this point the app is
      # deployed, tagged and pushed, and none of that comes back because a
      # Rust build or a phone did not cooperate. The run still ends non-zero,
      # so "it all worked" cannot be read off the exit status.
      if [ "$PLATFORMS" = 1 ] && [ "$T" != "MyCalMind" ]; then
        if sh bin/build-platforms.sh "$T"; then
          PLATFORM_OK="$PLATFORM_OK $T"
        else
          echo "   PLATFORM BUILD FAILED for $T — the release itself shipped" >&2
          PLATFORM_BAD="$PLATFORM_BAD $T"
        fi
      fi
      ;;
  esac
done

echo ""
echo "────────────────────────────────"
echo "$LANE complete:$PLAN"
if [ "$PLATFORMS" = 1 ]; then
  [ -z "$PLATFORM_OK" ]  || echo "platforms built:$PLATFORM_OK"
  if [ -n "$PLATFORM_BAD" ]; then
    echo "platforms FAILED:$PLATFORM_BAD (their releases shipped; the builds did not)" >&2
    exit 1
  fi
fi
