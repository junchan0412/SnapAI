#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

RUN_PACKAGE=1
REQUIRE_CLEAN=0
REQUIRE_SYNCED=0

usage() {
  cat <<'USAGE'
Usage: scripts/preflight-release.sh [--skip-package] [--require-clean] [--require-synced]

Runs the release readiness gate:
  1. git diff --check
  2. logic tests
  3. swift build
  4. app bundle build
  5. codesign verification
  6. release package + manifest verification

Options:
  --skip-package   Skip release zip/manifest packaging.
  --require-clean   Fail if tracked or untracked changes are present.
  --require-synced  Fetch tags and fail unless HEAD matches its upstream.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-package)
      RUN_PACKAGE=0
      ;;
    --require-clean)
      REQUIRE_CLEAN=1
      ;;
    --require-synced)
      REQUIRE_SYNCED=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

step() {
  echo ""
  echo "==> $1"
}

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

if [ "$REQUIRE_CLEAN" -eq 1 ]; then
  step "检查工作区是否干净"
  git diff --quiet
  git diff --cached --quiet
  if [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "error: 工作区存在未跟踪文件。请先提交、忽略或移除后再发版。" >&2
    git status --short
    exit 1
  fi
fi

if [ "$REQUIRE_SYNCED" -eq 1 ]; then
  step "检查当前分支与远端同步"
  git fetch --tags --prune
  UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
  if [ -z "$UPSTREAM" ]; then
    echo "error: 当前分支没有 upstream,无法确认 release 是否与远端一致。" >&2
    exit 1
  fi
  read -r AHEAD_COUNT BEHIND_COUNT < <(git rev-list --left-right --count "HEAD...$UPSTREAM")
  if [ "$AHEAD_COUNT" != "0" ] || [ "$BEHIND_COUNT" != "0" ]; then
    echo "error: 当前分支与 $UPSTREAM 不同步,禁止正式发版。" >&2
    echo "ahead:  $AHEAD_COUNT" >&2
    echo "behind: $BEHIND_COUNT" >&2
    echo "请先完成 rebase/merge、测试、提交并推送后再发版。" >&2
    exit 1
  fi
fi

step "检查源版本号"
SOURCE_VERSION=$(plist_value CFBundleShortVersionString Resources/Info.plist)
SOURCE_BUILD_VERSION=$(plist_value CFBundleVersion Resources/Info.plist)
validate_release_version "Resources/Info.plist" "$SOURCE_VERSION" "$SOURCE_BUILD_VERSION"

step "检查 diff 空白问题"
git diff --check

step "检查逻辑测试 target 边界"
scripts/check-logic-symlinks.sh

step "运行逻辑测试"
scripts/run-logic-tests.sh

step "运行 macOS smoke 测试"
scripts/run-macos-smoke-tests.sh --skip-logic

step "运行 SwiftPM 构建"
swift build

step "构建 release app bundle"
SNAPAI_RELEASE=1 ./build.sh --release

step "验证 app 签名"
codesign --verify --deep --strict --verbose=2 SnapAI.app

step "检查 app bundle 版本号"
APP_VERSION=$(plist_value CFBundleShortVersionString SnapAI.app/Contents/Info.plist)
APP_BUILD_VERSION=$(plist_value CFBundleVersion SnapAI.app/Contents/Info.plist)
validate_release_version "SnapAI.app" "$APP_VERSION" "$APP_BUILD_VERSION"
if [ "$APP_VERSION" != "$SOURCE_VERSION" ]; then
  echo "error: SnapAI.app 版本号与 Resources/Info.plist 不一致。" >&2
  echo "source: $SOURCE_VERSION" >&2
  echo "app:    $APP_VERSION" >&2
  exit 1
fi

VERSION="$SOURCE_VERSION"
TAG="v${VERSION#v}"
ZIP_PATH="dist/SnapAI-${TAG}.zip"
MANIFEST_PATH="dist/snapai-manifest-${TAG}.json"
MANIFEST_SIGNATURE_PATH="${MANIFEST_PATH}.sig"

if [ "$REQUIRE_SYNCED" -eq 1 ] && git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  TAG_COMMIT=$(git rev-list -n 1 "$TAG")
  HEAD_COMMIT=$(git rev-parse HEAD)
  if [ "$TAG_COMMIT" != "$HEAD_COMMIT" ]; then
    echo "error: 本地 tag $TAG 不指向当前 HEAD,禁止覆盖式发版。" >&2
    echo "tag:  $TAG_COMMIT" >&2
    echo "HEAD: $HEAD_COMMIT" >&2
    exit 1
  fi
fi

if [ "$RUN_PACKAGE" -eq 1 ]; then
  step "打包 release 资产"
  SNAPAI_RELEASE=1 scripts/package-release.sh "$VERSION"

  step "验证 release 资产"
  test -f "$ZIP_PATH"
  test -f "$MANIFEST_PATH"
  test -f "$MANIFEST_SIGNATURE_PATH"
  ACTUAL_SHA=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
  if ! grep -F "\"name\": \"$(basename "$ZIP_PATH")\"" "$MANIFEST_PATH" >/dev/null; then
    echo "error: manifest asset name 与 zip 文件名不一致。" >&2
    echo "zip asset: $(basename "$ZIP_PATH")" >&2
    echo "manifest:  $MANIFEST_PATH" >&2
    exit 1
  fi
  if ! grep -F "\"sha256\": \"$ACTUAL_SHA\"" "$MANIFEST_PATH" >/dev/null; then
    echo "error: manifest sha256 与 zip 不一致。" >&2
    echo "zip:      $ZIP_PATH" >&2
    echo "manifest: $MANIFEST_PATH" >&2
    echo "sha256:   $ACTUAL_SHA" >&2
    exit 1
  fi
  if ! grep -F "\"version\": \"$TAG\"" "$MANIFEST_PATH" >/dev/null; then
    echo "error: manifest version 与 Info.plist 不一致。" >&2
    echo "version:  $TAG" >&2
    echo "manifest: $MANIFEST_PATH" >&2
    exit 1
  fi
  if [ ! -s "$MANIFEST_SIGNATURE_PATH" ]; then
    echo "error: manifest 签名文件为空或不存在。" >&2
    echo "signature: $MANIFEST_SIGNATURE_PATH" >&2
    exit 1
  fi

  step "验证 release zip 可安装性"
  RELEASE_CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/snapai-release-check.XXXXXX")
  trap 'rm -rf "$RELEASE_CHECK_DIR"' EXIT
  /usr/bin/ditto -x -k "$ZIP_PATH" "$RELEASE_CHECK_DIR"
  if [ ! -d "$RELEASE_CHECK_DIR/SnapAI.app" ]; then
    echo "error: release zip 中未找到顶层 SnapAI.app。" >&2
    echo "zip: $ZIP_PATH" >&2
    find "$RELEASE_CHECK_DIR" -maxdepth 2 -print >&2
    exit 1
  fi
  TOP_LEVEL_COUNT=$(find "$RELEASE_CHECK_DIR" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
  if [ "$TOP_LEVEL_COUNT" != "1" ]; then
    echo "error: release zip 顶层包含非预期内容。" >&2
    find "$RELEASE_CHECK_DIR" -mindepth 1 -maxdepth 1 -print >&2
    exit 1
  fi
  ZIP_APP_VERSION=$(plist_value CFBundleShortVersionString "$RELEASE_CHECK_DIR/SnapAI.app/Contents/Info.plist")
  ZIP_APP_BUILD_VERSION=$(plist_value CFBundleVersion "$RELEASE_CHECK_DIR/SnapAI.app/Contents/Info.plist")
  validate_release_version "release zip SnapAI.app" "$ZIP_APP_VERSION" "$ZIP_APP_BUILD_VERSION"
  if [ "$ZIP_APP_VERSION" != "$SOURCE_VERSION" ]; then
    echo "error: release zip 中的 SnapAI.app 版本号与 Resources/Info.plist 不一致。" >&2
    echo "zip app: $ZIP_APP_VERSION" >&2
    echo "source:  $SOURCE_VERSION" >&2
    exit 1
  fi
  codesign --verify --deep --strict --verbose=2 "$RELEASE_CHECK_DIR/SnapAI.app"
fi

echo ""
echo "Preflight passed for ${TAG}"
