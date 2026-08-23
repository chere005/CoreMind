#!/bin/sh
# dtp the suite — deploy, tag, push, across every repo, in dependency order.
#
#   sh bin/dtp.sh all                every repo, core first
#   sh bin/dtp.sh CalMind            CalMind — and ChefMind, which depends on it
#   sh bin/dtp.sh --only AcctMind    that one alone
#   sh bin/dtp.sh all --plan         resolve the order and stop
#   sh bin/dtp.sh all --full         tdtp: the full test run in each lane
#   sh bin/dtp.sh all --platforms    …and build the platforms too: the macOS
#                                    bundle and the iOS build on the phone
#
# WHERE A PLATFORM BUILD ACTUALLY HAPPENS depends on the app. One carrying its
# own tools/build-platforms.sh ships itself — this script passes --platforms
# through to its lane and does not touch it otherwise. The rest are built here
# afterwards, out of bin/build-platforms.sh, until their repos grow the same
# file. ChefMind was the first, 2026-08-23.
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
  *" MyCalMind "*) echo "    (MyCalMind builds; its phone install stays the explicit tools/deploy-device.sh)" ;;
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

# The iPhone pre-flight is GONE (2026-08-23). It guarded the lane MyCalMind
# used to have — deploy-device.sh installing onto a connected phone, refusing
# without one, LAST, after everything else had shipped. MyCalMind ships itself
# now and its lane deliberately never touches a phone: iOS is build-only (an
# install would spend one of the 3 free-team slots), the phone install is the
# explicit tools/deploy-device.sh gesture and no release's side effect. A
# check for hardware nothing in the plan needs was refusing real releases.

[ "$PLANONLY" = 0 ] || exit 0

# ------------------------------------------------------- tell the status page
# Sean, 2026-08-22: the status page keeps the last 5 runs and paints one that
# is running right now purple. Reported from HERE rather than from each repo's
# own lane, because this is the thing that knows the whole plan — a run is
# "core, then the three web apps", not four unrelated releases.
#
# It cannot fail the release: report-status.sh warns and exits 0 on every path.
# The trap is what makes the purple honest — a lane that dies anywhere below,
# including on a `set -e` exit nobody wrote a handler for, still closes the run
# out instead of leaving it running for ever.
RUN_ID=$(sh bin/report-status.sh start "$(echo "$LANE" | tr 'A-Z' 'a-z')" "$(echo "$PLAN" | sed 's/^ *//')" 2>/dev/null || true)

# ------------------------------------------------------- the per-minute beat
# Sean, 2026-08-23: "i want an update per minute during any tdtp or dtp". A
# suite run takes twenty minutes and reported exactly twice — start and finish
# — so the page said "running" for all of it and could not say running WHAT.
#
# The lane writes its current phase to a file; a background loop pushes that
# file's contents once a minute. Two pieces rather than one because the lane
# is a sequence of long-running foreground commands (a full test suite, an
# rsync, an xcodebuild) and none of them can stop to report; the only thing
# that can report on a fixed clock is something else running alongside.
PHASE_FILE="$(pwd)/.status-phase"
phase() { printf '%s' "$*" > "$PHASE_FILE"; }
phase "starting"
BEAT_PID=""
if [ -n "$RUN_ID" ]; then
  (
    while :; do
      sleep 60
      [ -f "$PHASE_FILE" ] || exit 0
      sh bin/report-status.sh beat "$RUN_ID" "$(cat "$PHASE_FILE" 2>/dev/null)" >/dev/null 2>&1 || true
    done
  ) &
  BEAT_PID=$!
fi

stop_beat() {
  [ -n "$BEAT_PID" ] && kill "$BEAT_PID" >/dev/null 2>&1
  BEAT_PID=""
  rm -f "$PHASE_FILE"
}

report_fail() {
  stop_beat
  [ -n "$RUN_ID" ] || return 0
  sh bin/report-status.sh finish "$RUN_ID" failed 3 \
    "Stopped during $(cat "$PHASE_FILE" 2>/dev/null || echo "$PLAN"). Nothing after the failure was shipped; what ran before it was." 2>/dev/null || true
  RUN_ID=""
}
# The beat is killed on EVERY exit path, including the ones nobody wrote a
# handler for: a loop left running after the shell dies would keep a finished
# run painted purple until the next reboot.
trap report_fail EXIT INT TERM

PLATFORM_OK=""; PLATFORM_BAD=""
for T in $PLAN; do
  echo ""
  phase "$LANE $T — $(echo "$PLAN" | tr -s ' ' | sed 's/^ //') in this run"
  echo "──────────────────────────────── $LANE $T"
  case "$T" in
    core)
      # tdtp means the tests run. Without this the core lane tagged and pushed
      # a canon release having executed nothing — in the steady state the
      # pre-flight insists on, propagation writes no files and therefore
      # proves no consumer either.
      if [ "$FULL" = 1 ]; then
        echo "==> CoreMind's own suite"
        phase "core — running CoreMind's own suite"
        npm test
        npm run -s typecheck
      fi
      phase "core — propagating canon into the consumers"
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
      phase "$T — $([ "$FULL" = 1 ] && echo 'test run, then deploy, tag and push' || echo 'deploy, tag and push')"
      # DOES THE APP SHIP ITSELF? An app carrying its own
      # tools/build-platforms.sh owns every artifact it releases, and this
      # script's job for it is only to run its lane in the right ORDER among
      # the others — Sean, 2026-08-23: "This repo should be able to ship
      # itself (and needed dependencies) on its own... coremind is to ship all
      # apps simultaneously."
      #
      # Detected rather than listed. ChefMind grew the file first
      # (2026-08-23, morning); CalMind, AcctMind and MyCalMind grew theirs the
      # same day — every app ships itself now, and bin/build-platforms.sh
      # below is the fallback for a checkout that predates that.
      SELF_SHIPS=0
      [ -f "$R/tools/build-platforms.sh" ] && SELF_SHIPS=1
      # --platforms keeps its meaning for a self-shipping app by being passed
      # THROUGH: its lane builds everything when the flag is set and takes
      # --web (the release, no platform builds) when it is not. Without this
      # the flag would silently stop controlling half the suite.
      LANE_ARGS=""
      if [ "$SELF_SHIPS" = 1 ] && [ "$PLATFORMS" = 0 ]; then LANE_ARGS="--web"; fi
      if [ "$FULL" = 1 ]; then
        ( cd "$R" && sh tools/tdtp.sh $LANE_ARGS )
      else
        ( cd "$R" && sh tools/dtp.sh $LANE_ARGS )
      fi
      if [ "$SELF_SHIPS" = 1 ] && [ "$PLATFORMS" = 1 ]; then
        # Its own lane already did them, in the right place: the desktop
        # bundle before its tag, the device builds after its push.
        PLATFORM_OK="$PLATFORM_OK $T"
      fi
      # THE PLATFORMS THE RELEASE DID NOT SHIP. Run AFTER the lane, and its
      # failure is reported rather than fatal: by this point the app is
      # deployed, tagged and pushed, and none of that comes back because a
      # Rust build or a phone did not cooperate. The run still ends non-zero,
      # so "it all worked" cannot be read off the exit status.
      if [ "$PLATFORMS" = 1 ] && [ "$SELF_SHIPS" = 0 ] && [ "$T" != "MyCalMind" ]; then
        phase "$T — building the platforms its release does not ship"
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
fi

# Close the run out. A platform build that failed is severity 2, not 3: the
# releases shipped and are live — what did not happen is a desktop or device
# build, which is a thing to go and look at rather than a thing that is broken
# for anybody using the apps.
stop_beat
if [ -n "$RUN_ID" ]; then
  SUM="Shipped$PLAN."
  [ -z "$PLATFORM_OK" ] || SUM="$SUM Platforms built:$PLATFORM_OK."
  if [ -n "$PLATFORM_BAD" ]; then
    SUM="$SUM Platform builds FAILED:$PLATFORM_BAD — those releases are live, the builds are not."
    sh bin/report-status.sh finish "$RUN_ID" ok 2 "$SUM" 2>/dev/null || true
  else
    sh bin/report-status.sh finish "$RUN_ID" ok 0 "$SUM" 2>/dev/null || true
  fi
  RUN_ID=""
fi
trap - EXIT INT TERM

if [ "$PLATFORMS" = 1 ] && [ -n "$PLATFORM_BAD" ]; then
  echo "platforms FAILED:$PLATFORM_BAD (their releases shipped; the builds did not)" >&2
  exit 1
fi
