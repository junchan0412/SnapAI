#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
SNAPAI_CROSS_APP_BUILD_DIR="${1:-$PWD/.build/cross-app-runtime}"
if [ "$#" -gt 1 ] || [[ "$SNAPAI_CROSS_APP_BUILD_DIR" != /* ]]; then
  echo "Usage: scripts/prepare-cross-app-runtime.sh [absolute-output-directory]" >&2
  exit 2
fi
mkdir -p "$SNAPAI_CROSS_APP_BUILD_DIR"

SNAPAI_CROSS_APP_LOGIC_SOURCES=(
  Sources/SnapAILogic/TextCapture.swift
  Sources/SnapAILogic/ServicePasteboardText.swift
  Sources/SnapAILogic/TextWriteBackLogic.swift
  Sources/SnapAILogic/WriteBackCompatibility.swift
  Sources/SnapAILogic/MarkdownExportSafety.swift
  Sources/SnapAILogic/SensitiveTextSanitizer.swift
)

swiftc -O -whole-module-optimization -parse-as-library \
  -package-name snapai -module-name SnapAILogic \
  -emit-module -emit-module-path "$SNAPAI_CROSS_APP_BUILD_DIR/SnapAILogic.swiftmodule" \
  -emit-object "${SNAPAI_CROSS_APP_LOGIC_SOURCES[@]}" \
  -o "$SNAPAI_CROSS_APP_BUILD_DIR/SnapAILogic.o" \
  -framework AppKit -framework Carbon -framework ApplicationServices

swiftc -O -parse-as-library -package-name snapai \
  -I "$SNAPAI_CROSS_APP_BUILD_DIR" \
  Sources/SnapAI/TextEditTransaction.swift Tests/Runtime/CrossAppRuntime.swift \
  "$SNAPAI_CROSS_APP_BUILD_DIR/SnapAILogic.o" \
  -o "$SNAPAI_CROSS_APP_BUILD_DIR/SnapAICrossAppRuntime" \
  -framework AppKit -framework Carbon -framework ApplicationServices

shasum -a 256 "${SNAPAI_CROSS_APP_LOGIC_SOURCES[@]}" \
  Sources/SnapAI/TextEditTransaction.swift Tests/Runtime/CrossAppRuntime.swift \
  > "$SNAPAI_CROSS_APP_BUILD_DIR/sources.sha256"
printf 'Prepared: %s/SnapAICrossAppRuntime\n' "$SNAPAI_CROSS_APP_BUILD_DIR"
