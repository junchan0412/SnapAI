#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/configure-swift-toolchain.sh
if [ "$#" -gt 1 ]; then
  echo "usage: $0 [baseline-git-ref]" >&2
  exit 2
fi
SNAPAI_STORAGE_BENCH_DIR=$(mktemp -d "${TMPDIR:-/tmp}/snapai-storage-bench.XXXXXX")
trap 'rm -rf "$SNAPAI_STORAGE_BENCH_DIR"' EXIT
export SNAPAI_STORAGE_BENCH_DIR

compile_benchmark() {
  local source_root="$1"
  local destination="$2"
  swiftc -O -parse-as-library -package-name SnapAI \
    "$source_root"/Sources/SnapAILogic/*.swift Tests/Performance/StorageBenchmarks.swift \
    -o "$destination" -framework AppKit -framework Carbon \
    -framework ApplicationServices -framework ServiceManagement -lsqlite3
}

if [ "$#" -eq 1 ]; then
  SNAPAI_STORAGE_BASELINE_REF=$(git rev-parse --verify --end-of-options "$1^{commit}")
  export SNAPAI_STORAGE_BASELINE_REF
  mkdir -p "$SNAPAI_STORAGE_BENCH_DIR/baseline-source"
  git archive "$SNAPAI_STORAGE_BASELINE_REF" Sources/SnapAI Sources/SnapAILogic \
    | tar -x -C "$SNAPAI_STORAGE_BENCH_DIR/baseline-source"
  compile_benchmark "$SNAPAI_STORAGE_BENCH_DIR/baseline-source" "$SNAPAI_STORAGE_BENCH_DIR/before"
fi
compile_benchmark "$PWD" "$SNAPAI_STORAGE_BENCH_DIR/after"

python3 - <<'PY'
import json, os, pathlib, statistics, subprocess
root = pathlib.Path(os.environ['SNAPAI_STORAGE_BENCH_DIR'])
labels = ['before', 'after'] if (root / 'before').exists() else ['after']
runs = {label: [] for label in labels}
env = dict(os.environ, SNAPAI_LOGIC_TESTS='1')
for _ in range(5):
    for label in labels:
        runs[label].append(json.loads(subprocess.check_output([str(root / label)], env=env, text=True)))
median = {label: {key: statistics.median(row[key] for row in values) for key in values[0]} for label, values in runs.items()}
print(json.dumps({'baseline_commit': os.environ.get('SNAPAI_STORAGE_BASELINE_REF'),
                  'fixture': '500 HistoryEntry rows, 2 KB source and output, 5 alternating runs, swiftc -O',
                  'median_ms': median, 'runs_ms': runs}, indent=2))
PY
