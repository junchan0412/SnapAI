#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
source scripts/configure-swift-toolchain.sh

APP_NAME="SnapAI"
APP_BUNDLE="${APP_NAME}.app"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
RELEASE_BUILD="${SNAPAI_RELEASE:-0}"
CONFIGURATION="release"
LOCAL_IDENTITY_NAME="SnapAI Local Signing"

usage() {
  cat <<'USAGE'
Usage: ./build.sh [--release | --debug]

  --release  Build a distributable app with a stable signing identity.
  --debug    Build with debug symbols for local debugging and UI previews.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --release) RELEASE_BUILD=1 ;;
    --debug) CONFIGURATION="debug" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$RELEASE_BUILD" = "1" ] && [ "$CONFIGURATION" != "release" ]; then
  echo "error: 正式 release 必须使用 release configuration。" >&2
  exit 1
fi

if [ -z "$SIGN_IDENTITY" ] && security find-identity -p codesigning -v | rg -Fq "\"$LOCAL_IDENTITY_NAME\""; then
  SIGN_IDENTITY="$LOCAL_IDENTITY_NAME"
fi
if [ "$RELEASE_BUILD" = "1" ] && { [ -z "$SIGN_IDENTITY" ] || [ "$SIGN_IDENTITY" = "-" ]; }; then
  echo "error: 正式 release 需要稳定签名身份。请设置 CODESIGN_IDENTITY 或运行 scripts/create-local-signing-identity.sh。" >&2
  exit 1
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

printf '==> SwiftPM %s build (macOS 14+)\n' "$CONFIGURATION"
swift build -c "$CONFIGURATION"
BIN_DIR=$(swift build -c "$CONFIGURATION" --show-bin-path)
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/snapai-bundle.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/$APP_BUNDLE"

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Helpers" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/SnapAI" "$STAGED_APP/Contents/MacOS/SnapAI"
cp "$BIN_DIR/SnapAIUpdater" "$STAGED_APP/Contents/Helpers/SnapAIUpdater"
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SnapAIBuildConfiguration string $CONFIGURATION" "$STAGED_APP/Contents/Info.plist"
for asset in AppIconLight.png AppIconDark.png AppIconLight.icns AppIconDark.icns ManifestPublicKey.pem; do
  cp "Resources/$asset" "$STAGED_APP/Contents/Resources/$asset"
done
printf 'APPL????' > "$STAGED_APP/Contents/PkgInfo"

if [ "$CONFIGURATION" = "release" ]; then
  echo "==> 精简发行符号（dSYM 保留在 SwiftPM 构建目录）"
  xcrun strip -S -x "$STAGED_APP/Contents/MacOS/SnapAI"
  xcrun strip -S -x "$STAGED_APP/Contents/Helpers/SnapAIUpdater"
fi

printf '==> 签名 (%s)\n' "$SIGN_IDENTITY"
codesign --force --sign "$SIGN_IDENTITY" "$STAGED_APP/Contents/Helpers/SnapAIUpdater"
codesign --force --sign "$SIGN_IDENTITY" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

rm -rf "$APP_BUNDLE"
mv "$STAGED_APP" "$APP_BUNDLE"
printf '\n构建完成: %s/%s\n' "$PWD" "$APP_BUNDLE"
