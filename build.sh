#!/bin/bash
# 构建 SnapAI 并打包成 macOS .app
#
# 注意:本机仅安装了 Command Line Tools,其 SwiftPM (swift build) 存在缺陷
# (缺少 BuildServerProtocol.framework),因此这里直接用 swiftc 编译,稳定可靠。
set -e

cd "$(dirname "$0")"

APP_NAME="SnapAI"
BIN="/tmp/${APP_NAME}.bin"
APP_BUNDLE="${APP_NAME}.app"

echo "==> 编译 (swiftc -O) ..."
swiftc -O \
  Sources/SnapAI/*.swift \
  -o "${BIN}" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Carbon \
  -framework ApplicationServices

echo "==> 组装 .app bundle ..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BIN}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "Resources/AppIconLight.png" "${APP_BUNDLE}/Contents/Resources/AppIconLight.png"
cp "Resources/AppIconDark.png" "${APP_BUNDLE}/Contents/Resources/AppIconDark.png"
cp "Resources/AppIconLight.icns" "${APP_BUNDLE}/Contents/Resources/AppIconLight.icns"
cp "Resources/AppIconDark.icns" "${APP_BUNDLE}/Contents/Resources/AppIconDark.icns"
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

echo "==> ad-hoc 签名 (使辅助功能授权可被系统记忆) ..."
codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null \
  && echo "    已签名" \
  || echo "    (codesign 跳过/失败,不影响本机运行)"

echo ""
echo "构建完成: $(pwd)/${APP_BUNDLE}"
echo ""
echo "首次使用:"
echo "  1. 运行:  open ${APP_BUNDLE}"
echo "  2. 系统会提示授予「辅助功能」权限 —— 在系统设置中勾选 SnapAI"
echo "  3. 点击菜单栏 ✨ 图标 -> 设置,填入 API Key / 模型"
echo "  4. 在任意应用选中文字,按 ⌥A 提问 / ⌥T 翻译"
