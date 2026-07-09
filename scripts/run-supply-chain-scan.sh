#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEPS_JSON=$(swift package show-dependencies --format json)
DEPENDENCY_COUNT=$(DEPS_JSON="$DEPS_JSON" python3 - <<'PY'
import json
import os
print(len(json.loads(os.environ["DEPS_JSON"]).get("dependencies", [])))
PY
)

if [ "$DEPENDENCY_COUNT" = "0" ]; then
  echo "SwiftPM dependency scan: ok (no external SwiftPM dependencies)"
  exit 0
fi

if command -v osv-scanner >/dev/null 2>&1; then
  if [ -f Package.resolved ]; then
    osv-scanner --lockfile Package.resolved
  else
    osv-scanner .
  fi
  exit 0
fi

if [ "${SNAPAI_ALLOW_MISSING_VULN_SCANNER:-0}" = "1" ]; then
  echo "warning: SwiftPM dependencies exist, but no supported vulnerability scanner was found." >&2
  echo "warning: SNAPAI_ALLOW_MISSING_VULN_SCANNER=1 allowed this scan to continue." >&2
  exit 0
fi

echo "error: SwiftPM dependencies exist ($DEPENDENCY_COUNT), but no supported vulnerability scanner was found." >&2
echo "Install osv-scanner or set SNAPAI_ALLOW_MISSING_VULN_SCANNER=1 for an explicit local override." >&2
exit 1
