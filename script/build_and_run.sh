#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/build/module-cache"
mkdir -p build/module-cache build/pm-cache
if [[ "$MODE" == "--test" ]]; then exec ./script/test.sh; fi
swift build --disable-sandbox --cache-path "$ROOT_DIR/build/pm-cache" --scratch-path build/swiftpm -c release
BIN_DIR="$(swift build --disable-sandbox --cache-path "$ROOT_DIR/build/pm-cache" --scratch-path build/swiftpm -c release --show-bin-path)"
APP_BUNDLE="${HEADORBIT_APP_BUNDLE:-$ROOT_DIR/dist/HeadOrbit.app}"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_DIR/HeadOrbit" "$APP_BUNDLE/Contents/MacOS/HeadOrbit"
cp -R HeadOrbit/Resources/. "$APP_BUNDLE/Contents/Resources/"
cp LICENSE "$APP_BUNDLE/Contents/Resources/LICENSE"
python3 - "$APP_BUNDLE/Contents/Info.plist" <<'PY'
import plistlib,sys
with open('HeadOrbit/Info.plist','rb') as f:p=plistlib.load(f)
p['CFBundleExecutable']='HeadOrbit'
p['CFBundleIdentifier']='com.cogria.HeadOrbit'
with open(sys.argv[1],'wb') as f:plistlib.dump(p,f)
PY
/usr/bin/xattr -dr com.apple.FinderInfo "$APP_BUNDLE" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.ResourceFork "$APP_BUNDLE" 2>/dev/null || true
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"
if [[ "$MODE" == "--build" ]]; then echo "Built $APP_BUNDLE"; exit 0; fi
pkill -x HeadOrbit >/dev/null 2>&1 || true
case "$MODE" in
  run) open -n "$APP_BUNDLE" ;;
  --verify) open -n "$APP_BUNDLE"; sleep 1; pgrep -x HeadOrbit >/dev/null ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/HeadOrbit" ;;
  --logs|--telemetry)
    open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.cogria.HeadOrbit"'
    ;;
  *) echo 'Usage: script/build_and_run.sh [--build|--test|--verify|--debug|--logs|--telemetry]' >&2; exit 2 ;;
esac
