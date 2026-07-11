#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

target="${1:-SnapAI}"
label="${2:-runtime}"

if [[ "$target" =~ ^[0-9]+$ ]]; then
  pid="$target"
else
  pid=$(pgrep -x "$target" | head -n 1 || true)
fi

if [ -z "${pid:-}" ] || ! kill -0 "$pid" 2>/dev/null; then
  echo "error: no running process found for $target" >&2
  exit 1
fi

process_name=$(ps -o comm= -p "$pid" | sed 's#^.*/##')
rss_kb=$(ps -o rss= -p "$pid" | tr -d ' ')
cpu_percent=$(ps -o %cpu= -p "$pid" | tr -d ' ')
elapsed=$(ps -o etime= -p "$pid" | xargs)
footprint_output=$(footprint "$pid")
physical_footprint=$(awk -F': ' '/phys_footprint:/ { print $2; exit }' <<< "$footprint_output")
peak_footprint=$(awk -F': ' '/phys_footprint_peak:/ { print $2; exit }' <<< "$footprint_output")
vmmap_rows=$(vmmap -summary "$pid" \
  | awk '/^(CoreAnimation|Image IO|Malloc Large|Malloc Small |Malloc Small \(empty\)|TOTAL, minus reserved VM space)/')

cat <<EOF
# SnapAI Runtime Memory Snapshot

- Label: $label
- Process: $process_name
- PID: $pid
- Elapsed: $elapsed
- RSS: ${rss_kb} KB
- CPU: ${cpu_percent}%
- Physical footprint: ${physical_footprint:-unknown}
- Peak footprint: ${peak_footprint:-unknown}

## Selected VM regions

\`\`\`text
$vmmap_rows
\`\`\`
EOF
