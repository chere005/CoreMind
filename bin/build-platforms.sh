#!/bin/sh
# The platforms a release does NOT ship by itself: the macOS desktop bundle,
# the iOS build on the connected iPhone, and an Android build on an emulator.
#
#   sh bin/build-platforms.sh CalMind              all three, for that app
#   sh bin/build-platforms.sh CalMind --mac        just the desktop bundle
#   sh bin/build-platforms.sh CalMind --ios        just the phone
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
# stage. The only Mac path for an iOS-only app under a free team is "Designed
# for iPad" — and AcctMind's README already proved, the hard way, that build
# is where it ENDS: the product is a `platform 2` (iOS) Mach-O, and macOS's
# loader refuses to run one from a shell — "incorrect executable format",
# whether launched with `open` or registered with `lsregister` first. Running
# one locally is an XCODE GUI ACTION (Product > Destination > My Mac
# (Designed for iPad) > Run) with no command-line equivalent. So this script
# BUILDS it and stops; it does not copy anything into /Applications, because
# what it would copy cannot be opened from there. The table says `catalyst`
# for that case.
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

# The table. Where each app keeps its Expo project, how its Mac build works
# (a Tauri workspace name, "-" (no Mac target), or "catalyst" (build the iOS
# scheme for the Mac destination instead — MyCalMind's path)), and whether
# --ios should install onto the physical phone. MyCalMind's iOS build does
# NOT install: the free Apple dev team caps a device at 3 apps, that slot is
# already spent on CalMind/ChefMind/AcctMind, and MyCalMind's own deploy
# lane (tools/deploy-device.sh) is the one that manages that slot on
# purpose. This proves the build compiles and stops there.
case "$APP" in
  CalMind)   APPDIR="apps/app"; DESKTOP_WS="@calmind/desktop";  IOS_INSTALL=1 ;;
  ChefMind)  APPDIR="app";      DESKTOP_WS="@chefmind/desktop"; IOS_INSTALL=1 ;;
  AcctMind)  APPDIR="apps/app"; DESKTOP_WS="@acctmind/desktop"; IOS_INSTALL=1 ;;
  MyCalMind) APPDIR="app";      DESKTOP_WS="catalyst";          IOS_INSTALL=0 ;;
  *) echo "unknown app '$APP'" >&2; exit 1 ;;
esac
ROOT="$PARENT/$APP"
[ -d "$ROOT" ] || { echo "no checkout at $ROOT" >&2; exit 1; }

# Xcode derivedData for these builds is large (1-1.5G per app, per platform)
# and untracked — it was filling the internal disk across a long session of
# repeated builds. When a scratch volume is mounted, build there instead;
# otherwise fall back to the old in-repo location.
if [ -d /Volumes/SPACE ]; then
  BUILD_SCRATCH="/Volumes/SPACE/coremind-build/$APP"
  mkdir -p "$BUILD_SCRATCH"
else
  BUILD_SCRATCH="$ROOT/$APPDIR/ios"
fi

if [ "$DRY" = 1 ]; then
  if [ "$WANT_MAC" = 1 ]; then
    case "$DESKTOP_WS" in
      -)        echo "would: skip macOS — $APP has no desktop shell" ;;
      catalyst) echo "would: xcodebuild $APP for 'platform=macOS,variant=Designed for iPad' — BUILD ONLY, not launchable from a shell" ;;
      *)        echo "would: (cd $ROOT && npm -w $DESKTOP_WS run build)" ;;
    esac
  fi
  if [ "$WANT_IOS" = 1 ]; then
    if [ "$IOS_INSTALL" = 1 ]; then
      echo "would: prebuild $ROOT/$APPDIR (ios), xcodebuild Release, devicectl install"
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
IOS_WS=""
prebuild_ios() {
  [ -n "$IOS_WS" ] && return 0
  IOS_WS=$(ls -d "$ROOT/$APPDIR"/ios/*.xcworkspace 2>/dev/null | head -1)
  [ -n "$IOS_WS" ] && return 0
  # LANG is not optional: CocoaPods dies in unicode_normalize without a UTF-8
  # locale, naming nothing useful.
  ( cd "$ROOT/$APPDIR" && LANG=en_US.UTF-8 npx expo prebuild --platform ios --clean ) \
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
      echo "==> [$APP] macOS (Designed for iPad) — BUILD ONLY, see header"
      prebuild_ios || exit 1
      SCHEME=$(basename "$IOS_WS" .xcworkspace)
      DERIVED="$BUILD_SCRATCH/derived-mac"
      echo "    workspace: $(basename "$IOS_WS")  scheme: $SCHEME"

      LOG=$(mktemp -t coremind-mac)
      if ! xcodebuild -workspace "$IOS_WS" -scheme "$SCHEME" -configuration Release \
          -destination "platform=macOS,variant=Designed for iPad" \
          -derivedDataPath "$DERIVED" -allowProvisioningUpdates build >"$LOG" 2>&1; then
        echo "[$APP] the macOS (Designed for iPad) build failed — last lines:" >&2
        tail -25 "$LOG" >&2; echo "full log: $LOG" >&2; exit 1
      fi
      rm -f "$LOG"

      MACAPP=$(find "$DERIVED/Build/Products" -maxdepth 2 -name "$SCHEME.app" 2>/dev/null | head -1)
      [ -n "$MACAPP" ] || { echo "[$APP] the build succeeded and produced no $SCHEME.app" >&2; exit 1; }
      echo "    built: $MACAPP"
      echo "    NOT installed — proven unlaunchable from a shell (AcctMind's README);"
      echo "    open $IOS_WS in Xcode, pick My Mac (Designed for iPad), Run"
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
      ;;
  esac
fi

# --------------------------------------------------------------------- iOS
if [ "$WANT_IOS" = 1 ] && [ "$IOS_INSTALL" = 0 ]; then
  # MyCalMind: prove the iOS build compiles and stop there — see the app
  # table's comment for why nothing here touches the phone.
  echo "==> [$APP] iOS — BUILD ONLY, not installed (free-team device slot is spent)"
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
  echo "    NOT installed — MyCalMind's own device slot is managed by"
  echo "    tools/deploy-device.sh; run that if it should go on the phone"
fi

if [ "$WANT_IOS" = 1 ] && [ "$IOS_INSTALL" = 1 ]; then
  echo "==> [$APP] iOS"
  DEVJSON=$(mktemp -t coremind-devices)
  xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null 2>&1 \
    || { echo "devicectl cannot list devices — is Xcode installed?" >&2; exit 1; }
  # The UDID, not the CoreDevice identifier: xcodebuild's -destination matches
  # a physical device by UDID, and handing it the other one finds nothing.
  UDID=$(python3 - "$DEVJSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ok = [x['hardwareProperties']['udid'] for x in d.get('result', {}).get('devices', [])
      if x.get('hardwareProperties', {}).get('platform') == 'iOS'
      and x.get('connectionProperties', {}).get('tunnelState') in ('connected', 'available')
      and x.get('hardwareProperties', {}).get('udid')]
print(ok[0] if len(ok) == 1 else '')
PY
)
  rm -f "$DEVJSON"
  [ -n "$UDID" ] || { echo "[$APP] no single reachable iPhone — plug one in" >&2; exit 1; }
  echo "    device: $UDID"

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
  # devicectl installs onto a LOCKED phone; only launching needs it awake.
  xcrun devicectl device install app --device "$UDID" "$BUNDLE" \
    || { echo "[$APP] the install failed — is the phone paired with this Mac?" >&2; exit 1; }
  echo "    installed $SCHEME.app"
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
  # GRADLE_USER_HOME stays on the internal disk deliberately: a scratch
  # volume mounted exFAT (no atomic rename / proper file-locking semantics)
  # breaks gradle's cache and classpath-instrumentation writes outright —
  # proven on 2026-08-22, `mkdir` on it succeeds but gradle's directory
  # creation does not. Xcode's derivedDataPath (BUILD_SCRATCH above) has no
  # such problem, so that redirect stays; this one doesn't.
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
