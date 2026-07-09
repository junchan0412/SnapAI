#!/bin/bash
# 构建 SnapAI 并打包成 macOS .app
#
# 注意:本机仅安装了 Command Line Tools,其 SwiftPM (swift build) 存在缺陷
# (缺少 BuildServerProtocol.framework),因此这里直接用 swiftc 编译,稳定可靠。
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="SnapAI"
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/snapai-build.XXXXXX")
BIN="/tmp/${APP_NAME}.bin"
UPDATER_BIN="/tmp/${APP_NAME}Updater.bin"
LOGIC_OBJECT="${BUILD_DIR}/SnapAILogic.o"
APP_BUNDLE="${APP_NAME}.app"
LOCAL_IDENTITY_NAME="SnapAI Local Signing"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
RELEASE_BUILD="${SNAPAI_RELEASE:-0}"

trap 'rm -rf "${BUILD_DIR}"' EXIT

usage() {
  cat <<'USAGE'
Usage: ./build.sh [--release]

Options:
  --release  Build an official release bundle. Requires a stable code-signing
             identity and never falls back to ad-hoc signing.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --release)
      RELEASE_BUILD=1
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

echo "==> 编译 SnapAILogic module (swiftc -O) ..."
swiftc -O -whole-module-optimization -parse-as-library \
  -module-name SnapAILogic \
  -emit-module \
  -emit-module-path "${BUILD_DIR}/SnapAILogic.swiftmodule" \
  -emit-object Sources/SnapAILogic/*.swift \
  -o "${LOGIC_OBJECT}" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Carbon \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -lsqlite3

echo "==> 编译 SnapAI app (swiftc -O) ..."
swiftc -O \
  -I "${BUILD_DIR}" \
  Sources/SnapAI/*.swift \
  "${LOGIC_OBJECT}" \
  -o "${BIN}" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Carbon \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -lsqlite3

echo "==> 编译 updater helper ..."
swiftc -O \
  Sources/SnapAIUpdater/main.swift \
  -o "${UPDATER_BIN}"

echo "==> 组装 .app bundle ..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Helpers"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BIN}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${UPDATER_BIN}" "${APP_BUNDLE}/Contents/Helpers/${APP_NAME}Updater"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "Resources/AppIconLight.png" "${APP_BUNDLE}/Contents/Resources/AppIconLight.png"
cp "Resources/AppIconDark.png" "${APP_BUNDLE}/Contents/Resources/AppIconDark.png"
cp "Resources/AppIconLight.icns" "${APP_BUNDLE}/Contents/Resources/AppIconLight.icns"
cp "Resources/AppIconDark.icns" "${APP_BUNDLE}/Contents/Resources/AppIconDark.icns"
cp "Resources/ManifestPublicKey.pem" "${APP_BUNDLE}/Contents/Resources/ManifestPublicKey.pem"
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

if [ -z "${SIGN_IDENTITY}" ]; then
  if security find-identity -p codesigning -v | grep -F "\"${LOCAL_IDENTITY_NAME}\"" >/dev/null 2>&1; then
    SIGN_IDENTITY="${LOCAL_IDENTITY_NAME}"
  fi
fi

if [ -n "${SIGN_IDENTITY}" ]; then
  if [ "${RELEASE_BUILD}" = "1" ] && [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "error: 正式 release 构建禁止 ad-hoc 签名(CODESIGN_IDENTITY=-)。" >&2
    echo "请使用固定自签名证书,例如 ${LOCAL_IDENTITY_NAME}。" >&2
    exit 1
  fi
  echo "==> 稳定签名 (${SIGN_IDENTITY}) ..."
  codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}" \
    && echo "    已使用稳定签名"
else
  if [ "${RELEASE_BUILD}" = "1" ]; then
    echo "error: 正式 release 构建禁止 ad-hoc 签名,但未找到稳定签名身份。" >&2
    echo "请先运行 ./scripts/create-local-signing-identity.sh,或设置 CODESIGN_IDENTITY。" >&2
    exit 1
  fi
  echo "==> ad-hoc 签名 ..."
  codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null \
    && echo "    已 ad-hoc 签名" \
    || echo "    (codesign 跳过/失败,不影响本机运行)"
  echo "    提示: ad-hoc 签名每次构建都会改变代码身份,更新后可能需要重新授予辅助功能权限。"
  echo "    无 Apple 开发者账号时,可先运行:"
  echo "      ./scripts/create-local-signing-identity.sh"
  echo "    之后再构建,会使用稳定的本机自签名身份。"
fi

echo ""
echo "构建完成: $(pwd)/${APP_BUNDLE}"
echo ""
echo "首次使用:"
echo "  1. 运行:  open ${APP_BUNDLE}"
echo "  2. 系统会提示授予「辅助功能」权限 —— 在系统设置中勾选 SnapAI"
echo "  3. 点击菜单栏 ✨ 图标 -> 设置,填入 API Key / 模型"
echo "  4. 在任意应用选中文字,按 ⌥A 提问 / ⌥T 翻译"
