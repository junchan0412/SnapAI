#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/configure-swift-toolchain.sh
SURFACE="${1:-settings}"
APPEARANCE="${2:-light}"
PREVIEW_ARGS=(--preview "$SURFACE" --appearance "$APPEARANCE")
if [ "$#" -gt 2 ]; then PREVIEW_ARGS+=("${@:3}"); fi
PREVIEW_CONFIGURATION="${SNAPAI_PREVIEW_CONFIGURATION:-debug}"
BUILD_ARGS=(-c "$PREVIEW_CONFIGURATION")
case "$PREVIEW_CONFIGURATION" in
  debug) ;;
  release) BUILD_ARGS+=(-Xswiftc -DSNAPAI_PREVIEW) ;;
  *) echo 'error: SNAPAI_PREVIEW_CONFIGURATION must be debug or release' >&2; exit 1 ;;
esac
PREVIEW_APP="$PWD/dist/SnapAI Preview.app"
pkill -f "$PREVIEW_APP/Contents/MacOS/SnapAI" >/dev/null 2>&1 || true
swift build "${BUILD_ARGS[@]}"
BIN_DIR=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)
mkdir -p "$PREVIEW_APP/Contents/MacOS" "$PREVIEW_APP/Contents/Resources" "$PREVIEW_APP/Contents/Frameworks"
cp "$BIN_DIR/SnapAI" "$PREVIEW_APP/Contents/MacOS/SnapAI"
cp Resources/Info.plist "$PREVIEW_APP/Contents/Info.plist"
cp Resources/AppIconLight.icns "$PREVIEW_APP/Contents/Resources/"
for localization in Sources/SnapAI/Resources/*.lproj; do
  /usr/bin/ditto "$localization" "$PREVIEW_APP/Contents/Resources/$(basename "$localization")"
done
SPARKLE_FRAMEWORK=$(find .build/artifacts/sparkle -type d -name Sparkle.framework | head -n 1)
if [ -z "$SPARKLE_FRAMEWORK" ]; then
  echo 'error: Sparkle framework is missing after the preview build' >&2
  exit 1
fi
/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$PREVIEW_APP/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$PREVIEW_APP/Contents/MacOS/SnapAI" | grep -q '@executable_path/../Frameworks'; then
  xcrun install_name_tool -add_rpath '@executable_path/../Frameworks' "$PREVIEW_APP/Contents/MacOS/SnapAI"
fi
set_preview_plist_string() {
  /usr/libexec/PlistBuddy -c "Set :$1 $2" "$PREVIEW_APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PREVIEW_APP/Contents/Info.plist"
}
set_preview_plist_string CFBundleIdentifier com.snapai.preview
set_preview_plist_string CFBundleDisplayName 'SnapAI Preview'
set_preview_plist_string SnapAIBuildConfiguration "$PREVIEW_CONFIGURATION-preview"
codesign --force --deep --sign - "$PREVIEW_APP"
echo "SnapAI Preview: build=$PREVIEW_CONFIGURATION-preview, fixture=yes, network=no, surface=$SURFACE, appearance=$APPEARANCE"
open -n "$PREVIEW_APP" --args "${PREVIEW_ARGS[@]}"
