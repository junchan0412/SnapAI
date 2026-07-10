#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

MANIFEST="scripts/logic-symlink-manifest.txt"

unique_csv() {
  tr ' ' '\n' \
    | sed '/^$/d' \
    | sort -u \
    | paste -sd, -
}

top_level_types() {
  sed -nE 's/^[[:space:]]*(public[[:space:]]+)?(struct|enum|class|actor)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3/p' "$1"
}

printf '%-34s %-8s %-10s %-42s %s\n' "source" "status" "boundary" "symlink consumers" "app/test consumers"
printf '%-34s %-8s %-10s %-42s %s\n' "------" "------" "--------" "-----------------" "------------------"

while IFS= read -r file; do
  logic_path="Sources/SnapAILogic/$file"
  app_path="Sources/SnapAI/$file"
  [ -L "$logic_path" ] || continue
  [ -f "$app_path" ] || continue

  types=$(top_level_types "$app_path" | tr '\n' ' ')
  [ -n "$types" ] || continue

  symlink_consumers=""
  app_consumers=""

  for type_name in $types; do
    while IFS= read -r ref; do
      [ "$ref" = "$app_path" ] && continue
      base=$(basename "$ref")
      case "$ref" in
        Sources/SnapAI/*)
          if rg -qx "$base" "$MANIFEST" && [ -L "Sources/SnapAILogic/$base" ]; then
            symlink_consumers="$symlink_consumers $base"
          else
            app_consumers="$app_consumers $base"
          fi
          ;;
        Tests/SnapAILogicTests/*)
          app_consumers="$app_consumers $base"
          ;;
      esac
    done < <(rg -l "\\b${type_name}\\b" Sources/SnapAI Tests/SnapAILogicTests 2>/dev/null || true)
  done

  symlink_consumers=$(printf '%s' "$symlink_consumers" | unique_csv)
  app_consumers=$(printf '%s' "$app_consumers" | unique_csv)
  boundary="isolated"
  if [ -n "$symlink_consumers" ]; then
    status="blocked"
    boundary="cluster"
  elif [ -n "$app_consumers" ]; then
    status="bridge"
    boundary="app-api"
  else
    status="ready"
  fi

  printf '%-34s %-8s %-10s %-42s %s\n' "$file" "$status" "$boundary" "${symlink_consumers:-"-"}" "${app_consumers:-"-"}"
done < "$MANIFEST"
