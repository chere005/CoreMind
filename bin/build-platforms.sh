#!/bin/sh
# The platforms a release does NOT ship by itself: the macOS desktop bundle and
# the iOS build on the connected iPhone.
#
#   sh bin/build-platforms.sh CalMind            both, for that app
#   sh bin/build-platforms.sh CalMind --mac      just the desktop bundle
#   sh bin/build-platforms.sh CalMind --ios      just the phone
#   sh bin/build-platforms.sh CalMind --dry-run  print the plan
#
# WHY THIS LIVES HERE rather than three times over in the apps. A deploy script
# belongs to its app because its DESTINATIONS do — a production document root
# is the one thing that must never be built from a variable. A device build has
# no destination to get wrong: it puts a bundle on a phone that is plugged in,
# or it fails. So the machinery is shared and the differences are a table.
#
# NOT ANDROID. No emulator, no signing config and no attached device on this
# machine, so an "android" step here would be a step that has never run —
# which reads as covered and is not. It is named in the README as not covered.
set -e
cd "$(dirname "$0")/.."
PARENT="${MIND_DIR:-$(cd .. && pwd)}"

APP=""; WANT_MAC=1; WANT_IOS=1; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --mac)     WANT_IOS=0 ;;
    --ios)     WANT_MAC=0 ;;
    --dry-run) DRY=1 ;;
    -*) echo "unknown flag: $1" >&2; exit 1 ;;
    *)  APP="$1" ;;
  esac
  shift
done
[ -n "$APP" ] || { echo "name an app: CalMind, ChefMind, AcctMind, MyCalMind" >&2; exit 1; }

# The table. Where each app keeps its Expo project, and which desktop
# workspace builds its Mac bundle — "-" meaning it has none.
case "$APP" in
  CalMind)   APPDIR="apps/app"; DESKTOP_WS="@calmind/desktop" ;;
  ChefMind)  APPDIR="app";      DESKTOP_WS="@chefmind/desktop" ;;
  AcctMind)  APPDIR="apps/app"; DESKTOP_WS="@acctmind/desktop" ;;
  MyCalMind) APPDIR="app";      DESKTOP_WS="-" ;;
  *) echo "unknown app '$APP'" >&2; exit 1 ;;
esac
ROOT="$PARENT/$APP"
[ -d "$ROOT" ] || { echo "no checkout at $ROOT" >&2; exit 1; }

if [ "$DRY" = 1 ]; then
  [ "$WANT_MAC" = 1 ] && [ "$DESKTOP_WS" != "-" ] && echo "would: (cd $ROOT && npm -w $DESKTOP_WS run build)"
  [ "$WANT_MAC" = 1 ] && [ "$DESKTOP_WS" = "-" ] && echo "would: skip macOS — $APP has no desktop shell"
  [ "$WANT_IOS" = 1 ] && echo "would: prebuild $ROOT/$APPDIR, xcodebuild Release, devicectl install"
  exit 0
fi

# ------------------------------------------------------------------- macOS
if [ "$WANT_MAC" = 1 ]; then
  if [ "$DESKTOP_WS" = "-" ]; then
    echo "==> [$APP] macOS: no desktop shell in this app — skipped"
  else
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
  fi
fi

# --------------------------------------------------------------------- iOS
if [ "$WANT_IOS" = 1 ]; then
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

  # LANG is not optional: CocoaPods dies in unicode_normalize without a UTF-8
  # locale, naming nothing useful.
  ( cd "$ROOT/$APPDIR" && LANG=en_US.UTF-8 npx expo prebuild --platform ios --clean ) \
    || { echo "[$APP] prebuild failed" >&2; exit 1; }

  WS=$(ls -d "$ROOT/$APPDIR"/ios/*.xcworkspace 2>/dev/null | head -1)
  [ -n "$WS" ] || { echo "[$APP] prebuild produced no xcworkspace" >&2; exit 1; }
  SCHEME=$(basename "$WS" .xcworkspace)
  DERIVED="$ROOT/$APPDIR/ios/derived-platforms"
  echo "    workspace: $(basename "$WS")  scheme: $SCHEME"

  LOG=$(mktemp -t coremind-ios)
  # -destination with a SPECIFIC device, never -sdk: -sdk overrides SDKROOT for
  # every target in the scheme, so a watch complication compiles against the
  # iOS SDK and fails on code that is perfectly correct.
  if ! xcodebuild -workspace "$WS" -scheme "$SCHEME" -configuration Release \
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
