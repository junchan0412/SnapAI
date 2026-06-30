#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$2"
}

validate_release_version() {
  local label="$1"
  local short_version="$2"
  local build_version="$3"

  if [ -z "$short_version" ] || [ -z "$build_version" ]; then
    echo "error: $label 版本号为空。" >&2
    exit 1
  fi
  if [ "$short_version" != "$build_version" ]; then
    echo "error: $label CFBundleShortVersionString 与 CFBundleVersion 不一致。" >&2
    echo "short: $short_version" >&2
    echo "build: $build_version" >&2
    exit 1
  fi
  if ! [[ "$short_version" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
    echo "error: $label 版本号格式无效: $short_version" >&2
    echo "请使用正式版本号,例如 1.2.0。" >&2
    exit 1
  fi
}

verify_packaged_zip() {
  local zip_path="$1"
  local expected_version="$2"

  PACKAGE_CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/snapai-package-check.XXXXXX")
  trap 'rm -rf "${PACKAGE_CHECK_DIR:-}"' EXIT

  /usr/bin/ditto -x -k "$zip_path" "$PACKAGE_CHECK_DIR"
  if [ ! -d "$PACKAGE_CHECK_DIR/SnapAI.app" ]; then
    echo "error: release zip 中未找到顶层 SnapAI.app。" >&2
    echo "zip: $zip_path" >&2
    find "$PACKAGE_CHECK_DIR" -maxdepth 2 -print >&2
    exit 1
  fi

  local top_level_count
  top_level_count=$(find "$PACKAGE_CHECK_DIR" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
  if [ "$top_level_count" != "1" ]; then
    echo "error: release zip 顶层包含非预期内容。" >&2
    find "$PACKAGE_CHECK_DIR" -mindepth 1 -maxdepth 1 -print >&2
    exit 1
  fi

  local zip_app_version
  local zip_app_build_version
  zip_app_version=$(plist_value CFBundleShortVersionString "$PACKAGE_CHECK_DIR/SnapAI.app/Contents/Info.plist")
  zip_app_build_version=$(plist_value CFBundleVersion "$PACKAGE_CHECK_DIR/SnapAI.app/Contents/Info.plist")
  validate_release_version "release zip SnapAI.app" "$zip_app_version" "$zip_app_build_version"
  if [ "$zip_app_version" != "$expected_version" ]; then
    echo "error: release zip 中的 SnapAI.app 版本号与 Resources/Info.plist 不一致。" >&2
    echo "zip app: $zip_app_version" >&2
    echo "source:  $expected_version" >&2
    exit 1
  fi

  codesign --verify --deep --strict --verbose=2 "$PACKAGE_CHECK_DIR/SnapAI.app"
}

verify_manifest() {
  local zip_path="$1"
  local manifest_path="$2"
  local expected_tag="$3"
  local actual_sha
  local expected_asset_name

  if [ ! -f "$zip_path" ]; then
    echo "error: release zip 不存在: $zip_path" >&2
    exit 1
  fi
  if [ ! -f "$manifest_path" ]; then
    echo "error: manifest 不存在: $manifest_path" >&2
    exit 1
  fi

  expected_asset_name=$(basename "$zip_path")
  if ! grep -F "\"name\": \"$expected_asset_name\"" "$manifest_path" >/dev/null; then
    echo "error: manifest asset name 与 zip 文件名不一致。" >&2
    echo "zip asset: $expected_asset_name" >&2
    echo "manifest:  $manifest_path" >&2
    exit 1
  fi
  actual_sha=$(shasum -a 256 "$zip_path" | awk '{print $1}')
  if ! grep -F "\"sha256\": \"$actual_sha\"" "$manifest_path" >/dev/null; then
    echo "error: manifest sha256 与 zip 不一致。" >&2
    echo "zip:      $zip_path" >&2
    echo "manifest: $manifest_path" >&2
    echo "sha256:   $actual_sha" >&2
    exit 1
  fi
  if ! grep -F "\"version\": \"$expected_tag\"" "$manifest_path" >/dev/null; then
    echo "error: manifest version 与目标版本不一致。" >&2
    echo "version:  $expected_tag" >&2
    echo "manifest: $manifest_path" >&2
    exit 1
  fi
}

verify_manifest_signature() {
  local manifest_path="$1"
  local signature_path="$2"
  local private_key="$3"
  local verify_dir
  local public_key

  if [ ! -s "$signature_path" ]; then
    echo "error: manifest 签名文件为空或不存在: $signature_path" >&2
    exit 1
  fi

  verify_dir=$(mktemp -d "${TMPDIR:-/tmp}/snapai-manifest-signature-check.XXXXXX")
  public_key="$verify_dir/manifest.pub"
  if ! openssl pkey -in "$private_key" -pubout -out "$public_key" >/dev/null 2>&1; then
    rm -rf "$verify_dir"
    echo "error: 无法从 SNAPAI_MANIFEST_PRIVATE_KEY 导出公钥用于签名校验。" >&2
    exit 1
  fi
  if ! openssl pkeyutl -verify \
    -pubin \
    -inkey "$public_key" \
    -rawin \
    -in "$manifest_path" \
    -sigfile "$signature_path" >/dev/null 2>&1; then
    rm -rf "$verify_dir"
    echo "error: manifest 签名校验失败。" >&2
    echo "manifest:  $manifest_path" >&2
    echo "signature: $signature_path" >&2
    exit 1
  fi
  rm -rf "$verify_dir"
}

SOURCE_VERSION=$(plist_value CFBundleShortVersionString Resources/Info.plist)
SOURCE_BUILD_VERSION=$(plist_value CFBundleVersion Resources/Info.plist)
validate_release_version "Resources/Info.plist" "$SOURCE_VERSION" "$SOURCE_BUILD_VERSION"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION="$SOURCE_VERSION"
fi
VERSION="${VERSION#v}"

if [ "$VERSION" != "$SOURCE_VERSION" ]; then
  echo "error: 传入版本号与 Resources/Info.plist 不一致。" >&2
  echo "argument: $VERSION" >&2
  echo "source:   $SOURCE_VERSION" >&2
  exit 1
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

APP_VERSION=$(plist_value CFBundleShortVersionString "$APP_BUNDLE/Contents/Info.plist")
APP_BUILD_VERSION=$(plist_value CFBundleVersion "$APP_BUNDLE/Contents/Info.plist")
validate_release_version "$APP_BUNDLE" "$APP_VERSION" "$APP_BUILD_VERSION"
if [ "$APP_VERSION" != "$SOURCE_VERSION" ]; then
  echo "error: $APP_BUNDLE 版本号与 Resources/Info.plist 不一致。" >&2
  echo "app:    $APP_VERSION" >&2
  echo "source: $SOURCE_VERSION" >&2
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
  verify_manifest_signature "$DIST_DIR/$MANIFEST_NAME" "$DIST_DIR/$MANIFEST_NAME.sig" "$SNAPAI_MANIFEST_PRIVATE_KEY"
fi

verify_manifest "$DIST_DIR/$ZIP_NAME" "$DIST_DIR/$MANIFEST_NAME" "$TAG"
verify_packaged_zip "$DIST_DIR/$ZIP_NAME" "$SOURCE_VERSION"

echo "$DIST_DIR/$ZIP_NAME"
echo "$DIST_DIR/$MANIFEST_NAME"
if [ -f "$DIST_DIR/$MANIFEST_NAME.sig" ]; then
  echo "$DIST_DIR/$MANIFEST_NAME.sig"
fi
echo "sha256=$SHA256"
