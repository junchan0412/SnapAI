#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

MANIFEST="scripts/logic-symlink-manifest.txt"
CURRENT=$(mktemp "${TMPDIR:-/tmp}/snapai-logic-symlinks.XXXXXX")
trap 'rm -f "$CURRENT"' EXIT

find Sources/SnapAILogic -maxdepth 1 -type l -name '*.swift' -exec basename {} \; | sort > "$CURRENT"

if ! diff -u "$MANIFEST" "$CURRENT"; then
  echo "error: Sources/SnapAILogic symlink manifest is out of date." >&2
  echo "Add only logic-test-safe Swift files, then update $MANIFEST intentionally." >&2
  exit 1
fi

while IFS= read -r file; do
  path="Sources/SnapAILogic/$file"
  if [ ! -L "$path" ]; then
    echo "error: $path is not a symlink." >&2
    exit 1
  fi
  target=$(readlink "$path")
  if [[ "$target" != ../SnapAI/*.swift ]]; then
    echo "error: $path points outside Sources/SnapAI: $target" >&2
    exit 1
  fi
  if [ ! -f "$path" ]; then
    echo "error: $path points to a missing source file: $target" >&2
    exit 1
  fi
done < "$MANIFEST"

echo "SnapAILogic symlink manifest verified."
