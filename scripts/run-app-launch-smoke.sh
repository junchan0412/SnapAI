#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
APP_BUNDLE="${1:-SnapAI.app}"
if [ ! -d "$APP_BUNDLE" ]; then
  echo "error: app bundle 不存在: $APP_BUNDLE" >&2
  exit 1
fi
APP_BUNDLE=$(cd "$APP_BUNDLE" && pwd -P)
EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP_BUNDLE/Contents/Info.plist")
EXECUTABLE_PATH="$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_BUNDLE/Contents/Info.plist")
if [ ! -x "$EXECUTABLE_PATH" ]; then
  echo "error: app executable 不存在或不可执行: $EXECUTABLE_PATH" >&2
  exit 1
fi
if ! /usr/bin/grep -aFq 'SNAPAI_LAUNCH_SMOKE_DIRECTORY' "$EXECUTABLE_PATH" ||
   ! /usr/bin/grep -aFq 'SNAPAI_LAUNCH_SMOKE_TOKEN' "$EXECUTABLE_PATH"; then
  echo "error: app 不支持隔离启动验证。请先运行 ./build.sh --release。" >&2
  exit 1
fi

SMOKE_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/snapai-release-smoke.XXXXXX")
SMOKE_TOKEN=$(/usr/bin/uuidgen)
SMOKE_SUITE="com.snapai.release-smoke.$SMOKE_TOKEN"
NEW_PID=""

is_smoke_pid() {
  local pid="$1"
  local command_line
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  command_line=$(ps -ww -p "$pid" -o command= 2>/dev/null) || return 1
  [[ "$command_line" == "$EXECUTABLE_PATH"* ]] &&
    [[ "$command_line" == *"--release-smoke $SMOKE_TOKEN"* ]]
}

find_smoke_pid() {
  local candidate
  if [ -s "$SMOKE_DIRECTORY/pid" ]; then
    read -r candidate < "$SMOKE_DIRECTORY/pid"
    if [[ "$candidate" =~ ^[1-9][0-9]*$ ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  while IFS= read -r candidate; do
    if is_smoke_pid "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(pgrep -f -- "--release-smoke $SMOKE_TOKEN" 2>/dev/null || true)
  return 1
}

cleanup() {
  if [ -z "$NEW_PID" ]; then NEW_PID=$(find_smoke_pid || true); fi
  if is_smoke_pid "$NEW_PID"; then
    touch "$SMOKE_DIRECTORY/stop"
    for _ in $(seq 1 20); do
      is_smoke_pid "$NEW_PID" || break
      sleep 0.1
    done
  fi
  if is_smoke_pid "$NEW_PID"; then
    kill -TERM "$NEW_PID" 2>/dev/null || true
    sleep 0.2
  fi
  if is_smoke_pid "$NEW_PID"; then kill -KILL "$NEW_PID" 2>/dev/null || true; fi
  /usr/bin/defaults delete "$SMOKE_SUITE" >/dev/null 2>&1 || true
  if [[ "$NEW_PID" =~ ^[1-9][0-9]*$ ]] && [ -s "$SMOKE_DIRECTORY/support-directory" ]; then
    local support_directory
    local system_temp
    read -r support_directory < "$SMOKE_DIRECTORY/support-directory"
    system_temp=$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)
    system_temp=$(cd "$system_temp" && pwd -P)
    if [ "$support_directory" = "$system_temp/SnapAI-LogicTests-$NEW_PID" ] &&
       ! kill -0 "$NEW_PID" 2>/dev/null; then
      rm -rf "$support_directory"
    fi
  fi
  rm -rf "$SMOKE_DIRECTORY"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

/usr/bin/open -n -g -j \
  --env "SNAPAI_LOGIC_TESTS=1" \
  --env "SNAPAI_LAUNCH_SMOKE_DIRECTORY=$SMOKE_DIRECTORY" \
  --env "SNAPAI_LAUNCH_SMOKE_TOKEN=$SMOKE_TOKEN" \
  --stdout "$SMOKE_DIRECTORY/stdout.log" \
  --stderr "$SMOKE_DIRECTORY/stderr.log" \
  "$APP_BUNDLE" --args --release-smoke "$SMOKE_TOKEN"

READY=0
for _ in $(seq 1 200); do
  if [ -z "$NEW_PID" ]; then NEW_PID=$(find_smoke_pid || true); fi
  if [ -n "$NEW_PID" ] && ! is_smoke_pid "$NEW_PID"; then
    echo "error: app 在初始化完成前退出。" >&2
    tail -n 40 "$SMOKE_DIRECTORY/stderr.log" 2>/dev/null || true
    exit 1
  fi
  if [ -s "$SMOKE_DIRECTORY/ready" ]; then
    read -r ready_state ready_pid ready_token < "$SMOKE_DIRECTORY/ready"
    if [ "$ready_state" != "ready" ] || [ "$ready_pid" != "$NEW_PID" ] ||
       [ "$ready_token" != "$SMOKE_TOKEN" ]; then
      echo "error: app readiness marker 与本次启动不匹配。" >&2
      exit 1
    fi
    sleep 0.3
    if is_smoke_pid "$NEW_PID"; then READY=1; break; fi
    echo "error: app 初始化后立即退出。" >&2
    exit 1
  fi
  sleep 0.1
done

if [ "$READY" -ne 1 ]; then
  echo "error: app launch smoke 未收到真实 AppDelegate 的就绪标记。" >&2
  tail -n 40 "$SMOKE_DIRECTORY/stderr.log" 2>/dev/null || true
  exit 1
fi

echo "App initialized: ok (isolated settings, history, secrets and metrics)"
echo "Bundle id: $BUNDLE_ID"
echo "Launched pid: $NEW_PID"
touch "$SMOKE_DIRECTORY/stop"
for _ in $(seq 1 50); do
  if ! is_smoke_pid "$NEW_PID"; then
    echo "App terminate: ok"
    exit 0
  fi
  sleep 0.1
done
echo "error: app 未在正常退出请求后结束。" >&2
exit 1
