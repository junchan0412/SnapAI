#!/usr/bin/env bash
# 一键产出 release notes 截图:逐个 surface 起隔离预览进程,拿到窗口 ID 后
# 用 screencapture 直出 PNG,替代此前的手工 window-id + screencapture 流程。
#
# 用法:
#   scripts/screenshots-all.sh                       # light 外观,全部 surface
#   scripts/screenshots-all.sh dark                  # dark 外观,全部 surface
#   scripts/screenshots-all.sh light result quick    # 指定 surface
#   scripts/screenshots-all.sh light -c result       # -c 用预览的 --compact 尺寸
#
# 输出:docs/screenshots/snapai-<surface>-<appearance>.png
# 前置:屏幕录制权限(系统设置 → 隐私与安全性 → 屏幕录制)。
# 输出目录可用 SNAPAI_SCREENSHOT_DIR 覆盖(校验时不覆盖已发布截图)。
set -euo pipefail
cd "$(dirname "$0")/.."

appearance="light"
compact=0
surfaces=()

while [ $# -gt 0 ]; do
  case "$1" in
    light|dark) appearance="$1" ;;
    -c|--compact) compact=1 ;;
    -h|--help) grep -E '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "error: 未知选项 $1" >&2; exit 2 ;;
    *) surfaces+=("$1") ;;
  esac
  shift
done

if [ ${#surfaces[@]} -eq 0 ]; then
  surfaces=(settings provider model actions history-settings general permission
            result quick history commands welcome health diff update update-progress
            empty-history empty-settings)
fi

helper_bin="${TMPDIR:-/tmp}/snapai-window-id"
if [ ! -x "$helper_bin" ] || [ scripts/support/window-id.swift -nt "$helper_bin" ]; then
  xcrun swiftc -O scripts/support/window-id.swift -o "$helper_bin"
fi

preview_pattern="SnapAI Preview.app/Contents/MacOS/SnapAI"
output_dir="${SNAPAI_SCREENSHOT_DIR:-docs/screenshots}"
mkdir -p "$output_dir"

cleanup() {
  pkill -f "$preview_pattern" >/dev/null 2>&1 || true
}
trap cleanup EXIT

settle_seconds="${SNAPAI_SCREENSHOT_SETTLE:-10}"
written=()

for surface in "${surfaces[@]}"; do
  args=("$surface" "$appearance")
  if [ "$compact" -eq 1 ]; then args+=(--compact); fi
  scripts/run-ui-preview.sh "${args[@]}" >/dev/null 2>&1
  sleep "$settle_seconds"

  window_id=""
  for _ in $(seq 1 30); do
    window_id=$("$helper_bin" "SnapAI Preview" 2>/dev/null || true)
    [ -n "$window_id" ] && break
    sleep 0.5
  done
  if [ -z "$window_id" ]; then
    echo "error: $surface 没有拿到窗口 ID" >&2
    cleanup
    continue
  fi

  target="$output_dir/snapai-$surface-$appearance.png"
  if ! screencapture -x -o -l"$window_id" "$target"; then
    echo "error: $surface 截图失败(需要屏幕录制权限)" >&2
    cleanup
    continue
  fi
  size=$(sips -g pixelWidth -g pixelHeight "$target" | awk '/pixel/ {printf "%s ", $2}')
  echo "$target  ($size)"
  written+=("$target")
  cleanup
  sleep 1
done

echo ""
echo "已产出 ${#written[@]} 张截图 → $output_dir/"
