#!/bin/sh
# The platforms a release does NOT ship by itself: the macOS desktop bundle,
# the iOS build on every phone the app belongs on, and an Android build on an
# emulator.
#
# THE FALLBACK, AND THE ORIGIN. An app with its own tools/build-platforms.sh
# owns its artifacts and its lane builds them in the right places — the desktop
# bundle before the tag, the devices after the push — so bin/dtp.sh passes
# --platforms through and never calls this for it. ChefMind moved that way on
# 2026-08-23, after a release tagged and pushed while its Mac bundle stayed a
# day behind and had never heard of the Pantry tab; CalMind, AcctMind and
# MyCalMind moved the same day. ALL FOUR ship themselves now, so dtp calls this
# for none of them — it runs only for a checkout that predates that change.
#
# It is still the origin those four copies came down from, comments and all, so
# the table below stays complete rather than trimmed to whoever still needs it.
# A fix learned here is a copy-down into four repos, like packages/core.
#
#   sh bin/build-platforms.sh CalMind              all three, for that app
#   sh bin/build-platforms.sh CalMind --mac        just the desktop bundle
#   sh bin/build-platforms.sh CalMind --ios        just the phones
#   sh bin/build-platforms.sh CalMind --android    just the emulator
#   sh bin/build-platforms.sh CalMind --dry-run    print the plan
#
# Flags compose: `--ios --android` is those two, `--mac` alone is just that
# one. No flag at all means all three.
#
# WHY THIS LIVES HERE rather than three times over in the apps. A deploy script
# belongs to its app because its DESTINATIONS do — a production document root
# is the one thing that must never be built from a variable. A device or
# emulator build has no destination to get wrong: it puts a bundle on a phone
# that is plugged in, or an emulator that will boot, or it fails. So the
# machinery is shared and the differences are a table.
#
# MyCalMind's "macOS" is not a Tauri shell — it has no web export for one to
# stage. It is a REAL Mac Catalyst app: built for
# `platform=macOS,variant=Mac Catalyst,arch=arm64` and copied into
# /Applications like every other app's. The table says `catalyst` for it.
#
# THE ROUTE NOT TAKEN, recorded because this is the one it looks like from
# outside. "Designed for iPad" is the other Mac path for an iOS-only app, and
# it is a dead end from a script: AcctMind's README proved it the hard way —
# the product is a `platform 2` (iOS) Mach-O and macOS's loader
# refuses to run one from a shell, "incorrect executable format", whether
# launched with `open` or registered with `lsregister` first. Running one is an
# XCODE GUI ACTION (Product > Destination > My Mac (Designed for iPad) > Run)
# with no command-line equivalent. Catalyst is what made an installable Mac app
# possible instead — d26b647, 26 attempts and four distinct causes, handled
# below and by MyCalMind's own withMacCatalyst config plugin.
set -e
cd "$(dirname "$0")/.."
PARENT="${MIND_DIR:-$(cd .. && pwd)}"

# ------------------------------------------------------------------- argv
# Positive selection: naming a platform selects ONLY the named ones; naming
# none selects all three. (Zeroing the OTHERS per flag, the old two-platform
# scheme, does not compose past two — `--ios --android` would each zero the
# other and cancel out to nothing.)
APP=""; DRY=0; PICKED=0; WANT_MAC=0; WANT_IOS=0; WANT_ANDROID=0
while [ $# -gt 0 ]; do
  case "$1" in
    --mac)     WANT_MAC=1;     PICKED=1 ;;
    --ios)     WANT_IOS=1;     PICKED=1 ;;
    --android) WANT_ANDROID=1; PICKED=1 ;;
    --dry-run) DRY=1 ;;
    -*) echo "unknown flag: $1" >&2; exit 1 ;;
    *)  APP="$1" ;;
  esac
  shift
done
[ "$PICKED" = 1 ] || { WANT_MAC=1; WANT_IOS=1; WANT_ANDROID=1; }
[ -n "$APP" ] || { echo "name an app: CalMind, ChefMind, AcctMind, MyCalMind" >&2; exit 1; }

# THE HANDSETS, by udid. Sean, 2026-09-21, after a release reached one phone
# and stopped: "you should have dtp to all platforms and all 3 phones and my
# watch", then "no more caps per phone". Matched by UDID and never by name:
# two of these three names carry an apostrophe and one of those is the CURLY
# U+2018 the setup assistant produces rather than the ASCII one anybody types,
# so a name compares equal in a test written on this machine and then matches
# nothing on the day, and the phone goes without the release with nothing said.
SEAN_PHONE=00008130-000E3D060E20001C      # iPhoooooone
AUTUMN_PHONE=00008130-001A645E1E98001C    # Autumn's iPhone 15 Pro
PATRICIA_PHONE=00008130-0002605E0243001C  # Patricia's iPhone

# The table. Where each app keeps its Expo project, how its Mac build works
# (a Tauri workspace name, "-" (no Mac target), or "catalyst" (build the iOS
# scheme for the Mac destination instead — MyCalMind's path)), whether --ios
# should install onto physical phones, and WHICH ONES.
#
# That last column is the point of the 2026-09-21 change, and it is a fact
# about the APP, not about what happens to be plugged in: "the only apps
# installed on autumn's phone are ChefMind and CalMind", "patricia's phone
# only gets CalMind", "my phone gets all 6 (including the test ones)". A
# release is therefore neither "install to the phone" nor "install to every
# phone" — it is this list, minus whoever is switched off tonight.
#
# MyCalMind's iOS build still does NOT install, and the reason it used to give
# for that was wrong: it said the free Apple dev team caps a device at 3 apps
# and the slot was already spent on CalMind/ChefMind/AcctMind. The team these
# builds sign with, 2LGYTL3FSJ ("Sean Cheren"), is PAID — its Xcode-managed
# profile carries TimeToLive 365 where a personal team's carries 7 — so there
# is no slot and never was one to spend. What is true is the other half of
# that old sentence: MyCalMind's own lane (tools/deploy-device.sh) owns its
# device deploy, and two lanes pushing the same app to the same phone is how
# they disagree. This proves the build compiles and stops there.
case "$APP" in
  CalMind)   APPDIR="apps/app"; DESKTOP_WS="@calmind/desktop";  IOS_INSTALL=1; APP_PHONES="$SEAN_PHONE $AUTUMN_PHONE $PATRICIA_PHONE" ;;
  ChefMind)  APPDIR="app";      DESKTOP_WS="@chefmind/desktop"; IOS_INSTALL=1; APP_PHONES="$SEAN_PHONE $AUTUMN_PHONE" ;;
  AcctMind)  APPDIR="apps/app"; DESKTOP_WS="@acctmind/desktop"; IOS_INSTALL=1; APP_PHONES="$SEAN_PHONE" ;;
  MyCalMind) APPDIR="app";      DESKTOP_WS="catalyst";          IOS_INSTALL=0; APP_PHONES="" ;;
  *) echo "unknown app '$APP'" >&2; exit 1 ;;
esac
ROOT="$PARENT/$APP"
[ -d "$ROOT" ] || { echo "no checkout at $ROOT" >&2; exit 1; }

# Xcode derivedData stays on the INTERNAL disk, deliberately. A scratch
# volume mounted exFAT was tried on 2026-08-22 and reverted: exFAT can't
# store the extended attributes codesign needs, so any signed product
# (an app extension with entitlements, a hardened-runtime Catalyst build,
# a real device install) gets a "._<name>" AppleDouble sidecar file that
# codesign then tries to sign as a subcomponent and fails on — "code
# object is not signed at all". Same root cause that broke gradle's cache
# there earlier in the same session. Large and untracked (1-1.5G per app,
# per platform) is a real cost, but it has to be paid on APFS.
BUILD_SCRATCH="$ROOT/$APPDIR/ios"

if [ "$DRY" = 1 ]; then
  if [ "$WANT_MAC" = 1 ]; then
    case "$DESKTOP_WS" in
      -)        echo "would: skip macOS — $APP has no desktop shell" ;;
      catalyst) echo "would: source-build prebuild, patch-rndeps-catalyst.js, xcodebuild $APP for 'platform=macOS,variant=Mac Catalyst,arch=arm64', install to /Applications" ;;
      *)        echo "would: (cd $ROOT && npm -w $DESKTOP_WS run build), then install to /Applications" ;;
    esac
  fi
  if [ "$WANT_IOS" = 1 ]; then
    if [ "$IOS_INSTALL" = 1 ]; then
      echo "would: prebuild $ROOT/$APPDIR (ios), xcodebuild Release against one of $APP's phones, devicectl install that one bundle to each of them that answers"
    else
      echo "would: prebuild $ROOT/$APPDIR (ios), xcodebuild Release for generic/platform=iOS — BUILD ONLY, not installed"
    fi
  fi
  [ "$WANT_ANDROID" = 1 ] && echo "would: prebuild $ROOT/$APPDIR (android), gradlew assembleRelease, adb install"
  exit 0
fi

# --------------------------------------------------------------- the iOS project
# Shared by the iOS step AND MyCalMind's catalyst step, both of which build
# out of the SAME generated ios/ directory — prebuilt at most once per run.
# $1, if given, is extra "VAR=val VAR2=val2" env exported just for the
# prebuild command — MyCalMind's catalyst step needs
# EXPO_USE_PRECOMPILED_MODULES=0 RCT_USE_PREBUILT_RNCORE=0 (see its own
# comment below); a plain iOS build needs neither and stays fast.
IOS_WS=""
prebuild_ios() {
  [ -n "$IOS_WS" ] && return 0
  IOS_WS=$(ls -d "$ROOT/$APPDIR"/ios/*.xcworkspace 2>/dev/null | head -1)
  [ -n "$IOS_WS" ] && return 0
  # LANG is not optional: CocoaPods dies in unicode_normalize without a UTF-8
  # locale, naming nothing useful.
  ( cd "$ROOT/$APPDIR" && eval "${1:-}" LANG=en_US.UTF-8 npx expo prebuild --platform ios --clean ) \
    || { echo "[$APP] prebuild failed" >&2; return 1; }
  IOS_WS=$(ls -d "$ROOT/$APPDIR"/ios/*.xcworkspace 2>/dev/null | head -1)
  [ -n "$IOS_WS" ] || { echo "[$APP] prebuild produced no xcworkspace" >&2; return 1; }
}

# ------------------------------------------------------------------- macOS
if [ "$WANT_MAC" = 1 ]; then
  case "$DESKTOP_WS" in
    -)
      echo "==> [$APP] macOS: no desktop shell in this app — skipped"
      ;;
    catalyst)
      echo "==> [$APP] macOS (Mac Catalyst)"
      # Expo's prebuilt XCFrameworks (ExpoModulesCore, ExpoFont, ExpoFileSystem,
      # ExpoModulesWorklets) carry NO maccatalyst slice at all in this SDK
      # version — confirmed via ExpoModulesCore.xcframework's own Info.plist,
      # which lists only ios-arm64 and ios-arm64_x86_64-simulator — and their
      # CocoaPods-generated copy scripts have no code path for one either.
      # Building every module from source sidesteps that: ExpoModulesCore's
      # own podspec declares `:osx` support directly in its source_files
      # branch, and source compiles for whatever destination Xcode is asked
      # to target. RCT_USE_PREBUILT_RNCORE=0 does the same for React
      # Native's own core (its prebuilt React.xcframework hit the same
      # "bundle format is ambiguous" class of failure once ExpoModulesCore's
      # was fixed).
      prebuild_ios "EXPO_USE_PRECOMPILED_MODULES=0 RCT_USE_PREBUILT_RNCORE=0" || exit 1
      SCHEME=$(basename "$IOS_WS" .xcworkspace)
      DERIVED="$BUILD_SCRATCH/derived-mac"
      echo "    workspace: $(basename "$IOS_WS")  scheme: $SCHEME"

      # ReactNativeDependencies.xcframework (folly/glog/boost — React
      # Native's third-party C++ deps) has NO source-build option and DOES
      # ship a maccatalyst slice, but that slice's bundle is malformed —
      # see bin/patch-rndeps-catalyst.js for the full story and why the fix
      # has to be baked into its own "Replace React Native Dependencies"
      # build phase rather than just applied once before this build.
      node "$(dirname "$0")/patch-rndeps-catalyst.js" "$ROOT/$APPDIR/ios/Pods/Pods.xcodeproj/project.pbxproj" \
        || { echo "[$APP] could not patch ReactNativeDependencies' Catalyst bundle" >&2; exit 1; }

      LOG=$(mktemp -t coremind-mac)
      # arm64-only: see the ExpoModulesCore note above — there is no x86_64
      # Catalyst slice to link against either, so an x86_64 build attempt
      # fails deterministically, not intermittently. This machine is Apple
      # Silicon; arm64-only is the correct scope, not a workaround.
      if ! xcodebuild -workspace "$IOS_WS" -scheme "$SCHEME" -configuration Release \
          -destination "platform=macOS,variant=Mac Catalyst,arch=arm64" \
          -derivedDataPath "$DERIVED" ARCHS=arm64 \
          -allowProvisioningUpdates build >"$LOG" 2>&1; then
        echo "[$APP] the macOS (Mac Catalyst) build failed — last lines:" >&2
        tail -25 "$LOG" >&2; echo "full log: $LOG" >&2; exit 1
      fi
      rm -f "$LOG"

      MACAPP="$DERIVED/Build/Products/Release-maccatalyst/$SCHEME.app"
      [ -d "$MACAPP" ] || { echo "[$APP] the build succeeded and produced no $SCHEME.app" >&2; exit 1; }
      echo "    built: $MACAPP"
      rm -rf "/Applications/$SCHEME.app"
      cp -R "$MACAPP" /Applications/ \
        || { echo "[$APP] copying $SCHEME.app into /Applications failed" >&2; exit 1; }
      # Checked on disk, not taken on cp's exit status — the same verification
      # the Tauri branch below does, and what lets AGENTS.md say the copy is
      # verified for all four rather than for three of them.
      INSTALLED="/Applications/$SCHEME.app"
      [ -d "$INSTALLED" ] || { echo "[$APP] copy reported success but $INSTALLED is not there" >&2; exit 1; }
      echo "    installed: $INSTALLED"
      ;;
    *)
      echo "==> [$APP] macOS desktop bundle"
      # The export first: the shell stages whatever is in dist, so building
      # without one ships the last export rather than this release's.
      ( cd "$ROOT" && npm run -s export:web >/dev/null ) \
        || { echo "[$APP] the web export failed — not building the Mac bundle" >&2; exit 1; }
      ( cd "$ROOT" && npm -w "$DESKTOP_WS" run build ) \
        || { echo "[$APP] the macOS bundle failed to build" >&2; exit 1; }
      APPBUNDLE=$(ls -d "$ROOT"/desktop/src-tauri/target/release/bundle/macos/*.app 2>/dev/null | head -1)
      [ -n "$APPBUNDLE" ] || { echo "[$APP] the build reported success and produced no .app" >&2; exit 1; }
      echo "    $APPBUNDLE"
      # Its own smoke, where the app has one — CalMind and AcctMind do.
      if [ -f "$ROOT/desktop/smoke.sh" ]; then
        ( cd "$ROOT" && sh desktop/smoke.sh ) || { echo "[$APP] the macOS smoke failed" >&2; exit 1; }
      fi
      # INSTALL IT. A build sitting in target/release/bundle/macos/ is not a
      # deploy — nothing had ever put any of these three apps anywhere Sean
      # would see them. /Applications/<name>.app, replacing whatever build
      # was there before.
      rm -rf "/Applications/$(basename "$APPBUNDLE")"
      cp -R "$APPBUNDLE" /Applications/ \
        || { echo "[$APP] copying $(basename "$APPBUNDLE") into /Applications failed" >&2; exit 1; }
      INSTALLED="/Applications/$(basename "$APPBUNDLE")"
      [ -d "$INSTALLED" ] || { echo "[$APP] copy reported success but $INSTALLED is not there" >&2; exit 1; }
      echo "    installed: $INSTALLED"
      ;;
  esac
fi

# --------------------------------------------------------------------- iOS
if [ "$WANT_IOS" = 1 ] && [ "$IOS_INSTALL" = 0 ]; then
  # MyCalMind: prove the iOS build compiles and stop there — see the app
  # table's comment for why nothing here touches the phone.
  echo "==> [$APP] iOS — BUILD ONLY, not installed (its own lane owns the device deploy)"
  prebuild_ios || exit 1
  SCHEME=$(basename "$IOS_WS" .xcworkspace)
  DERIVED="$BUILD_SCRATCH/derived-platforms"
  echo "    workspace: $(basename "$IOS_WS")  scheme: $SCHEME"
  LOG=$(mktemp -t coremind-ios)
  if ! xcodebuild -workspace "$IOS_WS" -scheme "$SCHEME" -configuration Release \
      -destination "generic/platform=iOS" -derivedDataPath "$DERIVED" \
      -allowProvisioningUpdates build >"$LOG" 2>&1; then
    echo "[$APP] the iOS build failed — last lines:" >&2
    tail -25 "$LOG" >&2; echo "full log: $LOG" >&2; exit 1
  fi
  rm -f "$LOG"
  BUNDLE="$DERIVED/Build/Products/Release-iphoneos/$SCHEME.app"
  [ -d "$BUNDLE" ] || { echo "[$APP] the build succeeded and produced no $SCHEME.app" >&2; exit 1; }
  echo "    built: $BUNDLE"
  echo "    NOT installed — MyCalMind's device deploy belongs to its own"
  echo "    tools/deploy-device.sh; run that if it should go on the phone"
fi

if [ "$WANT_IOS" = 1 ] && [ "$IOS_INSTALL" = 1 ]; then
  echo "==> [$APP] iOS"
  # IOS_PHONES replaces the app's list wholesale for a one-off run; comments
  # are stripped whichever way it arrived, so a line copied out of the table
  # above keeps working when it is pasted into the environment.
  IOS_PHONES=$(printf '%s\n' "${IOS_PHONES:-$APP_PHONES}" | sed 's/#.*//')

  DEVJSON=$(mktemp -t coremind-devices)
  DEVLIST=$(mktemp -t coremind-ios-eligible)
  TAB=$(printf '\t')
  xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null 2>&1 \
    || { echo "devicectl cannot list devices — is Xcode installed?" >&2; exit 1; }
  # The UDID, not the CoreDevice identifier: xcodebuild's -destination matches
  # a physical device by UDID, and handing it the other one finds nothing.
  #
  # This step no longer CHOOSES a phone. It writes down every one that could
  # take an install and lets the list above decide, because both earlier
  # answers to "which phone?" were wrong in the same direction. Insisting on
  # EXACTLY one made a second paired handset refuse every install on this
  # machine — three releases in a row reported "no single reachable iPhone"
  # with the right phone sitting there the whole time (2026-08-23). Naming one
  # fixed that and quietly capped every release at a single phone, which is
  # what Sean caught on 2026-09-21.
  python3 - "$DEVJSON" > "$DEVLIST" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
# tunnelState: a paired phone that is merely idle lists as 'disconnected'
# until something warms the tunnel, so excluding it skipped the iOS step of
# CalMind 1.17.0 with the phone sitting right there (2026-08-30). Only
# 'unavailable' is a genuinely absent device.
for x in d.get('result', {}).get('devices', []):
    hw = x.get('hardwareProperties', {})
    if hw.get('platform') != 'iOS' or not hw.get('udid'):
        continue
    if x.get('connectionProperties', {}).get('tunnelState') not in ('connected', 'available', 'disconnected'):
        continue
    # 'or', not a get() default: a name key that is present and EMPTY would
    # come back as an empty name, and the shell below reads that as "devicectl
    # never mentioned this phone" and skips a handset that is sitting there.
    print(hw['udid'] + '\t' + (x.get('deviceProperties', {}).get('name') or '?'))
PY
  rm -f "$DEVJSON"

  # The name devicectl reported for a udid, and NOTHING for a udid it did not
  # report at all — an eligible device always has a name here, '?' standing in
  # for a nameless one, so empty means absent rather than anonymous. It
  # re-reads the file rather than walking a variable because these names
  # contain spaces and word-splitting would tear them in half.
  phone_name() {
    _name=""
    while IFS="$TAB" read -r _u _n; do
      if [ "$_u" = "$1" ]; then _name="$_n"; break; fi
    done < "$DEVLIST"
    printf '%s\n' "$_name"
  }

  # IOS_DEVICE narrows the run to ONE handset by name: how a person at the
  # keyboard says "this phone on the bench, never mind the routing", and how a
  # phone the team has never signed for gets registered (see the install
  # below). An ambiguous name refuses rather than guessing — the whole reason
  # the table is written in udids is that a name is not an identity.
  if [ -n "${IOS_DEVICE:-}" ]; then
    NARROWED=""; NARROWEDN=0
    while IFS="$TAB" read -r U N; do
      [ "$N" = "$IOS_DEVICE" ] || continue
      NARROWED="$U"; NARROWEDN=$((NARROWEDN + 1))
    done < "$DEVLIST"
    [ "$NARROWEDN" = 1 ] || {
      echo "[$APP] IOS_DEVICE='$IOS_DEVICE' matched $NARROWEDN reachable iPhones" >&2
      while IFS="$TAB" read -r U N; do echo "    seen: $N" >&2; done < "$DEVLIST"
      rm -f "$DEVLIST"; exit 1
    }
    IOS_PHONES="$NARROWED"
  fi

  # A phone on the list that devicectl does not report is SKIPPED with a note.
  # It is switched off, or off the network, or in somebody's bag — a normal
  # Tuesday, and not a reason to fail a release the other phones are waiting
  # for.
  UDID=""; TARGETS=""
  for P in $IOS_PHONES; do
    if [ -z "$(phone_name "$P")" ]; then
      echo "    skipping $P — devicectl does not report it (switched off, or off the network)"
      continue
    fi
    TARGETS="$TARGETS $P"
    [ -n "$UDID" ] || UDID="$P"
  done
  [ -n "$UDID" ] || {
    echo "[$APP] no usable iPhone: not one of the phones this app belongs on is reachable" >&2
    while IFS="$TAB" read -r U N; do echo "    seen: $N" >&2; done < "$DEVLIST"
    echo "  Plug one in, or name it:  IOS_DEVICE='Some iPhone' sh bin/build-platforms.sh $APP --ios" >&2
    rm -f "$DEVLIST"; exit 1
  }
  # ONE build for all of them. xcodebuild needs a single concrete destination
  # to sign against, but the profile it signs with lists every device the team
  # has registered rather than just the destination, so one build installs on
  # all of these phones. The first one that answered does the job and the rest
  # are served from its output; building per phone buys identical bundles.
  echo "    building against: $(phone_name "$UDID") ($UDID)"

  prebuild_ios || exit 1
  SCHEME=$(basename "$IOS_WS" .xcworkspace)

  # THE PLIST, checked here because here is where it means something. It goes
  # stale the moment a version bumps and only refreshes on a prebuild, so an
  # app whose `npm test` asserted it blocked its own next release. Right after
  # prebuild it must agree, and a binary about to go on a phone is exactly the
  # thing AGENTS.md's story is about: bump the config, build without
  # prebuilding, install a binary carrying the old number.
  if node -e "process.exit((require('$ROOT/package.json').scripts||{})['test:version:device']?0:1)" 2>/dev/null; then
    ( cd "$ROOT" && npm run -s test:version:device ) \
      || { echo "[$APP] the prebuild output disagrees with the version — not installing" >&2; exit 1; }
  fi

  DERIVED="$BUILD_SCRATCH/derived-platforms"
  echo "    workspace: $(basename "$IOS_WS")  scheme: $SCHEME"

  LOG=$(mktemp -t coremind-ios)
  # -destination with a SPECIFIC device, never -sdk: -sdk overrides SDKROOT for
  # every target in the scheme, so a watch complication compiles against the
  # iOS SDK and fails on code that is perfectly correct.
  if ! xcodebuild -workspace "$IOS_WS" -scheme "$SCHEME" -configuration Release \
      -destination "platform=iOS,id=$UDID" -derivedDataPath "$DERIVED" \
      -allowProvisioningUpdates build >"$LOG" 2>&1; then
    echo "[$APP] the iOS build failed — last lines:" >&2
    tail -25 "$LOG" >&2; echo "full log: $LOG" >&2; exit 1
  fi
  rm -f "$LOG"

  BUNDLE="$DERIVED/Build/Products/Release-iphoneos/$SCHEME.app"
  [ -d "$BUNDLE" ] || { echo "[$APP] the build succeeded and produced no $SCHEME.app" >&2; exit 1; }
  # ONE bundle, EVERY phone this app belongs on. devicectl installs onto a
  # LOCKED phone; only launching needs it awake.
  #
  # A handset the TEAM has never seen is refused outright, and devicectl says
  # so in provisioning language rather than saying "register this phone".
  # Registering one means BUILDING against it once — IOS_DEVICE='That iPhone'
  # makes it the destination — after which its udid is in every profile Xcode
  # regenerates and a plain install works. That is nearly always what a
  # warning below is really asking for.
  INSTALLED=0
  for P in $TARGETS; do
    PN=$(phone_name "$P")
    # Retried once, the same shape the watch install uses below: the first
    # call routinely times out enabling developer disk image services and
    # succeeds immediately afterwards.
    if xcrun devicectl device install app --device "$P" "$BUNDLE" </dev/null \
       || xcrun devicectl device install app --device "$P" "$BUNDLE" </dev/null; then
      INSTALLED=$((INSTALLED + 1))
      echo "    installed $SCHEME.app on $PN"
    else
      echo "[$APP] the install failed on $PN ($P) — is it paired with this Mac, and registered with the team? going on to the next phone" >&2
    fi
  done
  rm -f "$DEVLIST"
  # WHAT COUNTS AS A FAILED RELEASE. Two phones out of three SHIPPED — the
  # third is a warning above for somebody to chase, not a reason to throw away
  # a build the other two are already running. Only reaching NONE of them is
  # the failure the old single `exit 1` was catching, back when there was only
  # ever one phone for it to catch.
  [ "$INSTALLED" -gt 0 ] || { echo "[$APP] not one phone took $SCHEME.app" >&2; exit 1; }
  WATCHAPP=$(ls -d "$BUNDLE"/Watch/*.app 2>/dev/null | head -1)
  if [ -n "$WATCHAPP" ]; then
    echo "==> [$APP] watch app"
    WJSON=$(mktemp -t coremind-watch)
    xcrun devicectl list devices --json-output "$WJSON" >/dev/null 2>&1 || true
    WUDID=$(python3 - "$WJSON" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(''); raise SystemExit
ok = [x['hardwareProperties']['udid'] for x in d.get('result', {}).get('devices', [])
      if x.get('hardwareProperties', {}).get('platform') == 'watchOS'
      and x.get('hardwareProperties', {}).get('udid')]
print(ok[0] if len(ok) == 1 else '')
PY
)
    rm -f "$WJSON"
    if [ -n "$WUDID" ]; then
      # Retried once: the first call routinely times out enabling developer
      # disk image services and succeeds immediately afterwards.
      xcrun devicectl device install app --device "$WUDID" "$WATCHAPP" \
        || xcrun devicectl device install app --device "$WUDID" "$WATCHAPP" \
        || { echo "    the watch install failed — unlock the watch and retry:" >&2
             echo "      xcrun devicectl device install app --device $WUDID \"$WATCHAPP\"" >&2; }
    else
      echo "    no single watch found; install by hand:"
      echo "      xcrun devicectl device install app --device <watch-udid> \"$WATCHAPP\""
    fi
  fi
fi

# ----------------------------------------------------------------- Android
if [ "$WANT_ANDROID" = 1 ]; then
  echo "==> [$APP] Android"
  export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
  [ -d "$ANDROID_HOME" ] || { echo "[$APP] no Android SDK at \$ANDROID_HOME ($ANDROID_HOME)" >&2; exit 1; }
  command -v adb >/dev/null || { echo "[$APP] adb not on PATH under \$ANDROID_HOME" >&2; exit 1; }

  # A device already reachable — real hardware or an emulator someone left
  # running — wins outright; nothing here boots a second one on top of it.
  SERIAL=$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')
  if [ -z "$SERIAL" ]; then
    AVD="${ANDROID_AVD:-}"
    if [ -z "$AVD" ]; then
      # `avdmanager` reports a system image as installed from its OWN
      # metadata, which can be stale — one on this machine names a directory
      # that does not exist. So each candidate is checked on DISK, not taken
      # on the SDK's word, and the first one that is actually there wins.
      for CAND in $(emulator -list-avds 2>/dev/null); do
        IMG=$(sed -n 's/^image\.sysdir\.1=//p' "$HOME/.android/avd/$CAND.avd/config.ini" 2>/dev/null)
        if [ -n "$IMG" ] && [ -d "$ANDROID_HOME/$IMG" ]; then AVD="$CAND"; break; fi
      done
    fi
    [ -n "$AVD" ] || { echo "[$APP] no Android emulator running and no bootable AVD found — is one configured?" >&2; exit 1; }
    echo "    booting $AVD"
    nohup emulator -avd "$AVD" -no-snapshot-load -no-boot-anim -netdelay none -netspeed full \
      >"/tmp/coremind-emulator-$AVD.log" 2>&1 &
    disown
    i=0
    while [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
      sleep 5; i=$((i + 1))
      [ "$i" -le 72 ] || { echo "[$APP] $AVD did not finish booting within 6 minutes" >&2; exit 1; }
    done
    SERIAL=$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')
    [ -n "$SERIAL" ] || { echo "[$APP] $AVD booted but adb sees no device" >&2; exit 1; }
  fi
  echo "    device: $SERIAL"

  ( cd "$ROOT/$APPDIR" && LANG=en_US.UTF-8 npx expo prebuild --platform android --clean ) \
    || { echo "[$APP] android prebuild failed" >&2; exit 1; }

  # `assembleRelease`, not debug: every app's gradle here signs BOTH build
  # types with the auto-generated debug keystore (there is no release keystore
  # anywhere in the suite — none has ever been generated), so release installs
  # exactly as easily and is the configuration a real release would use.
  # GRADLE_USER_HOME stays on the internal disk too, same reasoning as
  # BUILD_SCRATCH above: a scratch volume mounted exFAT (no atomic rename,
  # no extended attributes) breaks gradle's cache and classpath-
  # instrumentation writes outright — proven 2026-08-22, `mkdir` on it
  # succeeds but gradle's directory creation does not.
  ( cd "$ROOT/$APPDIR/android" && ANDROID_HOME="$ANDROID_HOME" ./gradlew assembleRelease ) \
    || { echo "[$APP] the Android build failed" >&2; exit 1; }

  APK=$(find "$ROOT/$APPDIR/android/app/build/outputs/apk" -name "*.apk" 2>/dev/null | head -1)
  [ -n "$APK" ] || { echo "[$APP] the Android build produced no APK" >&2; exit 1; }

  # Package and launch activity read OFF THE BUILT APK via aapt, not guessed
  # from app.json or a manifest path — the source of truth for what just got
  # built, not what was asked for.
  AAPT=$(ls "$ANDROID_HOME"/build-tools/*/aapt 2>/dev/null | sort -V | tail -1)
  [ -n "$AAPT" ] || { echo "[$APP] no aapt under \$ANDROID_HOME/build-tools" >&2; exit 1; }
  BADGING=$("$AAPT" dump badging "$APK")
  PKG=$(printf '%s\n' "$BADGING" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
  ACTIVITY=$(printf '%s\n' "$BADGING" | sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p")
  [ -n "$PKG" ] && [ -n "$ACTIVITY" ] \
    || { echo "[$APP] could not read package/activity from the built APK" >&2; exit 1; }

  adb -s "$SERIAL" install -r "$APK" \
    || { echo "[$APP] adb install failed" >&2; exit 1; }
  adb -s "$SERIAL" shell am start -n "$PKG/$ACTIVITY" >/dev/null \
    || { echo "[$APP] the app installed but would not launch" >&2; exit 1; }
  # Polled, not one sleep-then-check: a cold RN launch on an emulator loads a
  # dozen native libraries (libreactnative.so, the codegen libs, JSI) before
  # the process is fully up, and 5 seconds flat once reported "not running"
  # for a process `ps` showed alive and loading cleanly a moment later. `ps`,
  # not `pidof` — this system image's pidof answered correctly on a SECOND
  # call at the same moment the first script run reported failure, which
  # points at the launch being mid-flight rather than the tool being broken.
  RUNNING=0
  for _ in 1 2 3 4 5 6; do
    if adb -s "$SERIAL" shell "ps -A" 2>/dev/null | grep -q "$PKG"; then RUNNING=1; break; fi
    sleep 3
  done
  [ "$RUNNING" = 1 ] \
    || { echo "[$APP] installed and launched but never showed up running" >&2; exit 1; }
  echo "    installed and running: $PKG on $SERIAL"
fi
