#!/usr/bin/env bash
# 冷启动耗时采样:用隔离 HOME 跑 N 次 release 二进制,收集 stderr 上的
# LaunchTiming 行(exec→就绪 / dyld+init / 装配),输出 min、中位数、max。
#
# 隔离 HOME 的原因:不动真实用户的设置与 iCloud 状态;代码路径与正常冷启动
# 一致(没有 launch smoke 的隔离持久化步骤),只有 onboarding 首启窗口会晚于
# 采样点出现,不影响计时。
#
# 用法:scripts/measure-startup.sh [次数] [app bundle 路径]
# 结果写入 docs/STARTUP_BASELINE.md(手工同步)。
set -euo pipefail
cd "$(dirname "$0")/.."

runs="${1:-7}"
bundle="${2:-SnapAI.app}"
executable="$bundle/Contents/MacOS/SnapAI"

if [ ! -x "$executable" ]; then
  echo "error: 找不到可执行文件 $executable(先运行 SNAPAI_RELEASE=1 ./build.sh --release)" >&2
  exit 1
fi

samples=()
cleanup() {
  [ -n "${pid:-}" ] && kill -9 "$pid" 2>/dev/null || true
  [ -n "${home:-}" ] && rm -rf "$home" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 "$runs"); do
  home=$(mktemp -d "${TMPDIR:-/tmp}/snapai-startup.XXXXXX")
  log="$home/launch.log"
  pid=""
  HOME="$home" "$executable" >"$log" 2>&1 &
  pid=$!
  line=""
  for _ in $(seq 1 150); do
    line=$(grep -h "SnapAI launch:" "$log" 2>/dev/null | head -n 1 || true)
    [ -n "$line" ] && break
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 0.1
  done
  kill -9 "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  pid=""
  if [ -z "$line" ]; then
    echo "error: 第 $_ 次采样没有拿到启动打点" >&2
    sed -n 1,20p "$log" >&2 || true
    exit 1
  fi
  samples+=("$line")
  echo "$line"
  rm -rf "$home"
  home=""
done

echo ""
echo "== $runs 次采样聚合(exec->ready,ms) =="
printf '%s\n' "${samples[@]}" \
  | sed -E 's/.*exec->ready ([0-9]+) ms.*/\1/' \
  | sort -n \
  | awk -v n="$runs" '
      { v[NR] = $1; sum += $1 }
      END {
        if (NR == 0) exit 1
        median = (NR % 2) ? v[(NR + 1) / 2] : int((v[NR / 2] + v[NR / 2 + 1]) / 2 + 0.5)
        printf "min=%d median=%d max=%d mean=%.0f\n", v[1], median, v[NR], sum / NR
      }'
