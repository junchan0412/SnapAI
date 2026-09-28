#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/configure-swift-toolchain.sh

SNAPAI_APP_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/snapai-app-tests.XXXXXX")"
trap 'rm -rf "$SNAPAI_APP_TEST_DIR"' EXIT
SNAPAI_TEST_BUNDLE="$SNAPAI_APP_TEST_DIR/SnapAIRuntimeSmoke.app"
mkdir -p "$SNAPAI_TEST_BUNDLE/Contents/MacOS" "$SNAPAI_APP_TEST_DIR/fixtures"

swiftc -O -whole-module-optimization -parse-as-library -enable-testing \
  -package-name snapai -module-name SnapAILogic \
  -emit-module -emit-module-path "$SNAPAI_APP_TEST_DIR/SnapAILogic.swiftmodule" \
  -emit-object Sources/SnapAILogic/*.swift \
  -o "$SNAPAI_APP_TEST_DIR/SnapAILogic.o" \
  -framework AppKit -framework SwiftUI -framework Carbon \
  -framework ApplicationServices -framework ServiceManagement -framework Vision -framework NaturalLanguage -lsqlite3

# Sparkle 是 SPM 二进制 target:本脚本用裸 swiftc 编译应用源码,既拿不到模块,
# 也没人替它把框架放进测试 bundle。这里自己保证产物存在、-F 可见、并嵌进 bundle。
SPARKLE_FRAMEWORK=$(find .build/artifacts/sparkle -type d -name "Sparkle.framework" 2>/dev/null | head -n 1 || true)
if [ -z "$SPARKLE_FRAMEWORK" ]; then
  echo "==> 缺少 Sparkle 框架产物,先执行 swift build 拉取二进制 target"
  swift build >/dev/null
  SPARKLE_FRAMEWORK=$(find .build/artifacts/sparkle -type d -name "Sparkle.framework" | head -n 1 || true)
fi
if [ -z "$SPARKLE_FRAMEWORK" ]; then
  echo "error: 找不到 Sparkle.framework,无法编译应用源码。" >&2
  exit 1
fi
SPARKLE_DIR=$(dirname "$SPARKLE_FRAMEWORK")

SNAPAI_APP_TEST_SOURCES=()
for source_file in Sources/SnapAI/*.swift; do
  case "$source_file" in
    Sources/SnapAI/main.swift|Sources/SnapAI/AppPreview.swift) continue ;;
  esac
  SNAPAI_APP_TEST_SOURCES+=("$source_file")
done

swiftc -O -parse-as-library -package-name snapai \
  -I "$SNAPAI_APP_TEST_DIR" \
  -F "$SPARKLE_DIR" \
  "${SNAPAI_APP_TEST_SOURCES[@]}" \
  Tests/Runtime/HTTPStreamFixture.swift Tests/Runtime/AppRuntimeSmoke.swift \
  "$SNAPAI_APP_TEST_DIR/SnapAILogic.o" \
  -o "$SNAPAI_TEST_BUNDLE/Contents/MacOS/SnapAIRuntimeSmoke" \
  -framework AppKit -framework SwiftUI -framework Carbon \
  -framework ApplicationServices -framework ServiceManagement -framework Vision -framework NaturalLanguage -lsqlite3 \
  -F "$SPARKLE_DIR" -Xlinker -rpath -Xlinker "@executable_path/../Frameworks"

cat > "$SNAPAI_TEST_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.snapai.runtime-tests</string>
  <key>CFBundleName</key><string>SnapAI Runtime Tests</string>
  <key>CFBundleExecutable</key><string>SnapAIRuntimeSmoke</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST

xcrun strip -S -x "$SNAPAI_TEST_BUNDLE/Contents/MacOS/SnapAIRuntimeSmoke"
mkdir -p "$SNAPAI_TEST_BUNDLE/Contents/Frameworks"
rm -rf "$SNAPAI_TEST_BUNDLE/Contents/Frameworks/Sparkle.framework"
/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$SNAPAI_TEST_BUNDLE/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$SNAPAI_TEST_BUNDLE/Contents/MacOS/SnapAIRuntimeSmoke" | grep -q "@executable_path/../Frameworks"; then
  xcrun install_name_tool -add_rpath "@executable_path/../Frameworks" "$SNAPAI_TEST_BUNDLE/Contents/MacOS/SnapAIRuntimeSmoke"
fi
codesign --force --deep --sign - "$SNAPAI_TEST_BUNDLE" >/dev/null 2>&1
/usr/bin/open -n -W --env SNAPAI_LOGIC_TESTS=1 \
  --stdout "$SNAPAI_APP_TEST_DIR/stdout.log" --stderr "$SNAPAI_APP_TEST_DIR/stderr.log" \
  "$SNAPAI_TEST_BUNDLE" --args \
  --fixture-root "$SNAPAI_APP_TEST_DIR/fixtures" --results "$SNAPAI_APP_TEST_DIR/results.txt"

if [ ! -f "$SNAPAI_APP_TEST_DIR/results.txt" ]; then
  cat "$SNAPAI_APP_TEST_DIR/stderr.log" >&2
  echo "error: App runtime smoke did not finish" >&2
  exit 1
fi
cat "$SNAPAI_APP_TEST_DIR/results.txt"
IFS= read -r SNAPAI_APP_TEST_STATUS < "$SNAPAI_APP_TEST_DIR/results.txt"
case "$SNAPAI_APP_TEST_STATUS" in
  "PASS "*) ;;
  *) cat "$SNAPAI_APP_TEST_DIR/stderr.log" >&2; exit 1 ;;
esac
