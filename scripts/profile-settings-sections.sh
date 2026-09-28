#!/usr/bin/env bash
# 按 section 采样设置窗口 footprint,用来回答「NavigationSplitView 的 detail
# section 是否在切换前就全量构建」:每个 section 单独起一个隔离预览进程,
# 若全量构建,各 section footprint 应基本相同;若按需构建,数值随内容变化。
#
# 用法:scripts/profile-settings-sections.sh [等待秒数]
# 输出:每行一个 section 的 physical footprint / peak / RSS。
set -euo pipefail
cd "$(dirname "$0")/.."

wait_seconds="${1:-12}"
preview_pid_pattern="SnapAI Preview.app/Contents/MacOS/SnapAI"
sections=(model provider actions history-settings general permission)

cleanup() {
  pkill -f "$preview_pid_pattern" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf '%-20s %-12s %-12s %s\n' "section" "footprint" "peak" "RSS"
for section in "${sections[@]}"; do
  scripts/run-ui-preview.sh "$section" light >/dev/null 2>&1
  sleep "$wait_seconds"
  pid=$(pgrep -f "$preview_pid_pattern" | head -n 1 || true)
  if [ -z "${pid:-}" ]; then
    printf '%-20s %s\n' "$section" "launch failed"
    cleanup
    continue
  fi
  footprint_output=$(footprint "$pid")
  physical=$(awk -F': ' '/phys_footprint:/ { print $2; exit }' <<< "$footprint_output")
  peak=$(awk -F': ' '/phys_footprint_peak:/ { print $2; exit }' <<< "$footprint_output")
  rss=$(ps -o rss= -p "$pid" | tr -d ' ')
  printf '%-20s %-12s %-12s %s KB\n' "$section" "$physical" "$peak" "$rss"
  cleanup
  sleep 1
done
