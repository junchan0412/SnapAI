#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [ "${SNAPAI_MANUAL_TEST_RUNNER:-0}" != "1" ]; then
  source scripts/configure-swift-toolchain.sh
fi

if [ "${SNAPAI_MANUAL_TEST_RUNNER:-0}" != "1" ] && xcrun --find xctest >/dev/null 2>&1; then
  SNAPAI_LOGIC_TESTS=1 swift test --filter SnapAILogicTests
  exit 0
fi

echo "==> Running standalone logic test runner"

SNAPAI_LOGIC_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/snapai-logic-tests.XXXXXX")
trap 'rm -rf "$SNAPAI_LOGIC_TEST_DIR"' EXIT
OUT="$SNAPAI_LOGIC_TEST_DIR/SnapAILogicTests"
LOGIC_SOURCES=()
while IFS= read -r file; do
  LOGIC_SOURCES+=("$file")
done < <(find Sources/SnapAILogic \( -type f -o -type l \) -name '*.swift' | sort)
TEST_SOURCES=()
while IFS= read -r file; do
  TEST_SOURCES+=("$file")
done < <(find Tests/SnapAILogicTests -name '*.swift' -type f | sort)

swiftc -parse-as-library -package-name snapai -D SNAPAI_MANUAL_TEST_MAIN \
  "${LOGIC_SOURCES[@]}" \
  "${TEST_SOURCES[@]}" \
  -o "$OUT" \
  -framework AppKit \
  -framework Carbon \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -lsqlite3

SNAPAI_LOGIC_TESTS=1 "$OUT"
