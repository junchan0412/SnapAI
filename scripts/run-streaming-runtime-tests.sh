#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/configure-swift-toolchain.sh

SNAPAI_STREAM_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/snapai-stream-tests.XXXXXX")"
trap 'rm -rf "$SNAPAI_STREAM_TEST_DIR"' EXIT

swiftc -O -whole-module-optimization -parse-as-library -enable-testing \
  -package-name snapai -module-name SnapAILogic \
  -emit-module -emit-module-path "$SNAPAI_STREAM_TEST_DIR/SnapAILogic.swiftmodule" \
  -emit-object \
  Sources/SnapAILogic/*.swift \
  -o "$SNAPAI_STREAM_TEST_DIR/SnapAILogic.o" \
  -framework AppKit -framework Carbon -framework ApplicationServices \
  -framework ServiceManagement -lsqlite3

swiftc -O -parse-as-library -package-name snapai \
  -I "$SNAPAI_STREAM_TEST_DIR" \
  Sources/SnapAI/MarkdownPresentationModel.swift \
  Sources/SnapAI/ResultStreamingCoordinator.swift \
  Tests/Runtime/HTTPStreamFixture.swift \
  Tests/Runtime/StreamingRuntimeSmoke.swift \
  "$SNAPAI_STREAM_TEST_DIR/SnapAILogic.o" \
  -o "$SNAPAI_STREAM_TEST_DIR/StreamingRuntimeSmoke" \
  -framework AppKit -framework Carbon -framework ApplicationServices \
  -framework ServiceManagement -lsqlite3

SNAPAI_LOGIC_TESTS=1 "$SNAPAI_STREAM_TEST_DIR/StreamingRuntimeSmoke"
