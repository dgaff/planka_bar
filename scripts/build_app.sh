#!/bin/bash
# Builds PlankaBar.app from the Swift package and ad-hoc (self-)signs it.
# Usage: scripts/build_app.sh [clean] [debug|release]   (default: release)
#   clean  wipe .build first (needed after renaming/moving the repo, which
#          leaves stale absolute paths in the module cache)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/PlankaBar.app"

if [[ "${1:-}" == "clean" ]]; then
  echo "==> Cleaning $ROOT/.build"
  rm -rf "$ROOT/.build"
  shift
fi

CONFIG="${1:-release}"

echo "==> swift build -c $CONFIG"
swift build --package-path "$ROOT" -c "$CONFIG"

BIN="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)/PlankaBar"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PlankaBar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
echo "    Tip: move it to /Applications so 'Launch at startup' registers reliably:"
echo "    cp -R \"$APP\" /Applications/"
