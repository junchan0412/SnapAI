#!/usr/bin/env bash
# 无障碍走查:对指定 preview surface 起隔离进程,遍历窗口 AX 树(VoiceOver 朗读的就是
# 这棵树),报告「可交互但没有可读名称」的控件。默认走设置页 6 个 section + 主要面板。
#
# 用法:
#   scripts/ax-audit.sh                  # 全部默认 surface
#   scripts/ax-audit.sh model quick      # 指定 surface
#   scripts/ax-audit.sh --tree model     # 附带打印整棵树
#
# 退出码:0 = 无问题;1 = 存在无可读名称的控件;2 = 环境/启动失败。
# 需要辅助功能权限(系统设置 → 隐私与安全性 → 辅助功能)。
set -euo pipefail
cd "$(dirname "$0")/.."

tree=0
surfaces=()
while [ $# -gt 0 ]; do
  case "$1" in
    --tree) tree=1 ;;
    -h|--help) grep -E '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "error: 未知选项 $1" >&2; exit 2 ;;
    *) surfaces+=("$1") ;;
  esac
  shift
done
if [ ${#surfaces[@]} -eq 0 ]; then
  surfaces=(model provider actions history-settings general permission
            result quick history commands welcome health
            empty-settings empty-history update diff)
fi

helper_bin="${TMPDIR:-/tmp}/snapai-ax-audit"
if [ ! -x "$helper_bin" ] || [ scripts/support/ax-audit.swift -nt "$helper_bin" ]; then
  xcrun swiftc -O scripts/support/ax-audit.swift -o "$helper_bin"
fi

preview_pattern="SnapAI Preview.app/Contents/MacOS/SnapAI"
total=0
failed=0
cleanup() { pkill -f "$preview_pattern" >/dev/null 2>&1 || true; }
trap cleanup EXIT

for surface in "${surfaces[@]}"; do
  scripts/run-ui-preview.sh "$surface" light >/dev/null 2>&1
  sleep "${SNAPAI_AX_SETTLE:-8}"
  pid=$(pgrep -f "$preview_pattern" | head -n 1 || true)
  if [ -z "${pid:-}" ]; then
    echo "== $surface: 启动失败 =="
    failed=1
    continue
  fi
  echo "== $surface =="
  if [ "$tree" -eq 1 ]; then
    "$helper_bin" "$pid" --tree || failed=1
  else
    "$helper_bin" "$pid" || failed=1
  fi
  cleanup
  sleep 1
done

exit "$failed"
