#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
fi

TAG="v${VERSION#v}"
ZIP_NAME="SnapAI-${TAG}.zip"
MANIFEST_NAME="snapai-manifest-${TAG}.json"
DIST_DIR="dist"
APP_BUNDLE="SnapAI.app"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "error: $APP_BUNDLE not found; run ./build.sh first" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$ZIP_NAME" "$DIST_DIR/$MANIFEST_NAME" "$DIST_DIR/$MANIFEST_NAME.sig"

/usr/bin/xattr -cr "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

/usr/bin/ditto --norsrc --noextattr -c -k --keepParent "$APP_BUNDLE" "$DIST_DIR/$ZIP_NAME"
SHA256=$(shasum -a 256 "$DIST_DIR/$ZIP_NAME" | awk '{print $1}')

cat > "$DIST_DIR/$MANIFEST_NAME" <<JSON
{
  "version": "$TAG",
  "assets": [
    {
      "name": "$ZIP_NAME",
      "sha256": "$SHA256"
    }
  ]
}
JSON

if [ -n "${SNAPAI_MANIFEST_PRIVATE_KEY:-}" ]; then
  openssl pkeyutl -sign \
    -inkey "$SNAPAI_MANIFEST_PRIVATE_KEY" \
    -rawin \
    -in "$DIST_DIR/$MANIFEST_NAME" \
    -out "$DIST_DIR/$MANIFEST_NAME.sig"
fi

echo "$DIST_DIR/$ZIP_NAME"
echo "$DIST_DIR/$MANIFEST_NAME"
if [ -f "$DIST_DIR/$MANIFEST_NAME.sig" ]; then
  echo "$DIST_DIR/$MANIFEST_NAME.sig"
fi
echo "sha256=$SHA256"
