#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_BUNDLE="${1:-SnapAI.app}"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "error: app bundle 不存在: $APP_BUNDLE" >&2
  exit 1
fi

EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP_BUNDLE/Contents/Info.plist")
EXECUTABLE_PATH="$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_BUNDLE/Contents/Info.plist")

if [ ! -x "$EXECUTABLE_PATH" ]; then
  echo "error: app executable 不存在或不可执行: $EXECUTABLE_PATH" >&2
  exit 1
fi

pid_list_for_executable() {
  pgrep -f "$EXECUTABLE_PATH" 2>/dev/null | sort || true
}

contains_pid() {
  local needle="$1"
  local haystack="$2"
  grep -qx "$needle" <<<"$haystack"
}

BEFORE_PIDS=$(pid_list_for_executable)

/usr/bin/open -n -g "$APP_BUNDLE"

NEW_PID=""
for _ in $(seq 1 50); do
  AFTER_PIDS=$(pid_list_for_executable)
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    if ! contains_pid "$pid" "$BEFORE_PIDS"; then
      NEW_PID="$pid"
      break
    fi
  done <<<"$AFTER_PIDS"
  [ -n "$NEW_PID" ] && break
  sleep 0.2
done

if [ -z "$NEW_PID" ]; then
  echo "error: app launch smoke 未检测到新进程。" >&2
  echo "bundle: $APP_BUNDLE" >&2
  echo "bundle id: $BUNDLE_ID" >&2
  exit 1
fi

echo "App launch: ok"
echo "Bundle id: $BUNDLE_ID"
echo "Launched pid: $NEW_PID"

kill -TERM "$NEW_PID" 2>/dev/null || true
for _ in $(seq 1 20); do
  if ! kill -0 "$NEW_PID" 2>/dev/null; then
    echo "App terminate: ok"
    exit 0
  fi
  sleep 0.1
done

kill -KILL "$NEW_PID" 2>/dev/null || true
echo "App terminate: forced"
