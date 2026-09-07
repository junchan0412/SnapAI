#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [ "$#" -gt 1 ]; then
  echo "usage: $0 [baseline-git-ref]" >&2
  exit 2
fi

SNAPAI_BENCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/snapai-stream-bench.XXXXXX")"
trap 'rm -rf "$SNAPAI_BENCH_DIR"' EXIT

if [ "$#" -eq 1 ]; then
  SNAPAI_BENCH_REF="$(git rev-parse --verify --end-of-options "$1^{commit}")"
  for source_file in StreamingAccumulator MarkdownPresentation; do
    git show "$SNAPAI_BENCH_REF:Sources/SnapAILogic/${source_file}.swift" \
      > "$SNAPAI_BENCH_DIR/${source_file}.swift"
  done
  swiftc -O -parse-as-library "$SNAPAI_BENCH_DIR/StreamingAccumulator.swift" \
    "$SNAPAI_BENCH_DIR/MarkdownPresentation.swift" Tests/Performance/StreamingBenchmarks.swift \
    -o "$SNAPAI_BENCH_DIR/baseline"
  echo "Baseline $SNAPAI_BENCH_REF"
  "$SNAPAI_BENCH_DIR/baseline"
fi

swiftc -O -parse-as-library Sources/SnapAILogic/StreamingAccumulator.swift \
  Sources/SnapAILogic/MarkdownPresentation.swift Tests/Performance/StreamingBenchmarks.swift \
  -o "$SNAPAI_BENCH_DIR/current"
echo "Current working tree"
"$SNAPAI_BENCH_DIR/current"
