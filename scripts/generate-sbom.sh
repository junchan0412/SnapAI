#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
ZIP_PATH="${2:-}"
OUTPUT_PATH="${3:-}"

if [ -z "$VERSION" ] || [ -z "$ZIP_PATH" ] || [ -z "$OUTPUT_PATH" ]; then
  echo "Usage: scripts/generate-sbom.sh <version> <zip-path> <output-path>" >&2
  exit 2
fi

if [ ! -f "$ZIP_PATH" ]; then
  echo "error: zip 不存在: $ZIP_PATH" >&2
  exit 1
fi

DEPS_JSON=$(swift package show-dependencies --format json)
GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
ZIP_SHA256=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
PACKAGE_SHA256=$(shasum -a 256 Package.swift | awk '{print $1}')
INFO_PLIST_SHA256=$(shasum -a 256 Resources/Info.plist | awk '{print $1}')
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export SNAPAI_SBOM_VERSION="$VERSION"
export SNAPAI_SBOM_ZIP_NAME="$(basename "$ZIP_PATH")"
export SNAPAI_SBOM_ZIP_SHA256="$ZIP_SHA256"
export SNAPAI_SBOM_PACKAGE_SHA256="$PACKAGE_SHA256"
export SNAPAI_SBOM_INFO_PLIST_SHA256="$INFO_PLIST_SHA256"
export SNAPAI_SBOM_GIT_COMMIT="$GIT_COMMIT"
export SNAPAI_SBOM_GENERATED_AT="$GENERATED_AT"
export SNAPAI_SBOM_DEPS_JSON="$DEPS_JSON"
export SNAPAI_SBOM_OUTPUT="$OUTPUT_PATH"

python3 - <<'PY'
import json
import os
from pathlib import Path

deps = json.loads(os.environ["SNAPAI_SBOM_DEPS_JSON"])
version = os.environ["SNAPAI_SBOM_VERSION"]
zip_name = os.environ["SNAPAI_SBOM_ZIP_NAME"]

components = [
    {
        "type": "application",
        "name": "SnapAI",
        "version": version,
        "bom-ref": "pkg:generic/snapai@" + version,
        "hashes": [
            {"alg": "SHA-256", "content": os.environ["SNAPAI_SBOM_ZIP_SHA256"]}
        ],
        "properties": [
            {"name": "release.asset", "value": zip_name},
            {"name": "git.commit", "value": os.environ["SNAPAI_SBOM_GIT_COMMIT"]},
        ],
    },
    {
        "type": "file",
        "name": "Package.swift",
        "bom-ref": "file:Package.swift",
        "hashes": [
            {"alg": "SHA-256", "content": os.environ["SNAPAI_SBOM_PACKAGE_SHA256"]}
        ],
    },
    {
        "type": "file",
        "name": "Resources/Info.plist",
        "bom-ref": "file:Resources/Info.plist",
        "hashes": [
            {"alg": "SHA-256", "content": os.environ["SNAPAI_SBOM_INFO_PLIST_SHA256"]}
        ],
    },
]

for dep in deps.get("dependencies", []):
    identity = dep.get("identity") or dep.get("name") or "unknown"
    components.append(
        {
            "type": "library",
            "name": dep.get("name") or identity,
            "version": dep.get("version") or "unspecified",
            "bom-ref": "pkg:swift/" + identity,
            "purl": "pkg:swift/" + identity,
            "externalReferences": [
                {"type": "vcs", "url": dep.get("url") or dep.get("path") or ""}
            ],
        }
    )

bom = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.5",
    "serialNumber": "urn:uuid:" + os.environ["SNAPAI_SBOM_GIT_COMMIT"][:32].ljust(32, "0"),
    "version": 1,
    "metadata": {
        "timestamp": os.environ["SNAPAI_SBOM_GENERATED_AT"],
        "component": components[0],
        "properties": [
            {"name": "swiftpm.dependencies.count", "value": str(len(deps.get("dependencies", [])))},
            {"name": "swiftpm.identity", "value": deps.get("identity", "snapai")},
        ],
    },
    "components": components,
    "dependencies": [
        {
            "ref": components[0]["bom-ref"],
            "dependsOn": [component["bom-ref"] for component in components[1:]],
        }
    ],
}

output = Path(os.environ["SNAPAI_SBOM_OUTPUT"])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(bom, ensure_ascii=False, indent=2) + "\n")
PY

echo "$OUTPUT_PATH"
