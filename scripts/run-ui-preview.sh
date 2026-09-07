#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/configure-swift-toolchain.sh
SURFACE="${1:-settings}"
APPEARANCE="${2:-light}"
PREVIEW_ARGS=(--preview "$SURFACE" --appearance "$APPEARANCE")
if [ "${3:-}" = "--compact" ]; then PREVIEW_ARGS+=(--compact); fi
PREVIEW_APP="$PWD/dist/SnapAI Preview.app"
pkill -f "$PREVIEW_APP/Contents/MacOS/SnapAI" >/dev/null 2>&1 || true
swift build
BIN_DIR=$(swift build --show-bin-path)
mkdir -p "$PREVIEW_APP/Contents/MacOS" "$PREVIEW_APP/Contents/Resources"
cp "$BIN_DIR/SnapAI" "$PREVIEW_APP/Contents/MacOS/SnapAI"
cp Resources/Info.plist "$PREVIEW_APP/Contents/Info.plist"
cp Resources/AppIconLight.icns "$PREVIEW_APP/Contents/Resources/"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.snapai.preview' "$PREVIEW_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName SnapAI Preview' "$PREVIEW_APP/Contents/Info.plist"
codesign --force --sign - "$PREVIEW_APP"
open -n "$PREVIEW_APP" --args "${PREVIEW_ARGS[@]}"
