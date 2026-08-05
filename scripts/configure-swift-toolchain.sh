#!/bin/bash

# Source this file before Swift app builds. Recent Command Line Tools SDKs can
# expose SwiftUI without shipping SwiftUIMacros, which fails on every @State.

snapai_swiftui_probe() {
  printf '%s\n' \
    'import SwiftUI' \
    'struct SnapAIToolchainProbe: View {' \
    '  @State private var value = false' \
    '  var body: some View { Text(value.description) }' \
    '}' \
    | swiftc -typecheck - >/dev/null 2>&1
}

snapai_configure_swift_toolchain() {
  if [ -n "${DEVELOPER_DIR:-}" ] && [ ! -d "$DEVELOPER_DIR" ]; then
    echo "error: DEVELOPER_DIR 不存在: $DEVELOPER_DIR" >&2
    return 1
  fi

  if snapai_swiftui_probe; then
    return 0
  fi

  if [ -n "${DEVELOPER_DIR:-}" ]; then
    echo "error: 当前 DEVELOPER_DIR 缺少可用的 SwiftUIMacros: $DEVELOPER_DIR" >&2
    echo "请改为完整 Xcode 的 Contents/Developer 目录。" >&2
    return 1
  fi

  local app_path
  while IFS= read -r app_path; do
    [ -n "$app_path" ] || continue
    [ -d "$app_path/Contents/Developer" ] || continue
    export DEVELOPER_DIR="$app_path/Contents/Developer"
    if snapai_swiftui_probe; then
      echo "==> 自动使用完整 Xcode toolchain: $DEVELOPER_DIR"
      return 0
    fi
    unset DEVELOPER_DIR
  done < <(
    find /Applications -maxdepth 1 -type d -name 'Xcode*.app' 2>/dev/null
    if command -v mdfind >/dev/null 2>&1; then
      mdfind 'kMDItemCFBundleIdentifier == "com.apple.dt.Xcode"'
    fi
  )

  echo "error: 当前 Swift toolchain 无法加载 SwiftUIMacros,且未找到可用的完整 Xcode。" >&2
  echo "请安装 Xcode,或设置 DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer。" >&2
  return 1
}

snapai_configure_swift_toolchain
unset -f snapai_swiftui_probe snapai_configure_swift_toolchain
