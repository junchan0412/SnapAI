#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if swift -e 'import XCTest' >/dev/null 2>&1; then
  SNAPAI_LOGIC_TESTS=1 swift test --filter SnapAILogicTests
  exit 0
fi

echo "warning: XCTest module is unavailable in this toolchain; using swiftc compatibility runner." >&2

OUT="/tmp/SnapAILogicTests"
LOGIC_SOURCES=()
while IFS= read -r file; do
  LOGIC_SOURCES+=("$file")
done < <(find Sources/SnapAILogic \( -type f -o -type l \) -name '*.swift' | sort)
TEST_SOURCES=()
while IFS= read -r file; do
  TEST_SOURCES+=("$file")
done < <(find Tests/SnapAILogicTests -name '*.swift' -type f | sort)

swiftc -D SNAPAI_MANUAL_TEST_MAIN \
  "${LOGIC_SOURCES[@]}" \
  "${TEST_SOURCES[@]}" \
  -o "$OUT" \
  -framework AppKit \
  -framework Carbon \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -framework Security \
  -lsqlite3

SNAPAI_LOGIC_TESTS=1 "$OUT"
