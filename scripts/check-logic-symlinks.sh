#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
from collections import defaultdict
from pathlib import Path
import fnmatch
import re
import sys

root = Path.cwd()
logic = root / "Sources/SnapAILogic"
app = root / "Sources/SnapAI"
manifest = root / "scripts/logic-symlink-manifest.txt"
errors = []
expected = manifest.read_text().splitlines()
sources = sorted(logic.glob("*.swift"))
actual = [source.name for source in sources]
if expected != actual:
    errors.append("SnapAILogic source manifest does not match its real source files")
    errors.extend(f"  missing: {name}" for name in sorted(set(expected) - set(actual)))
    errors.extend(f"  unlisted: {name}" for name in sorted(set(actual) - set(expected)))

for source in logic.rglob("*"):
    if source.is_symlink():
        errors.append(f"shared logic must be a real source, not a symlink: {source.relative_to(root)}")

forbidden_files = (
    "AppDelegate*.swift", "*View.swift", "*Window.swift", "*Panel.swift",
    "?*SettingsSection.swift", "CommandPalette.swift", "HotKeyRecorder.swift",
    "MenuCoordinator.swift", "QuickInput.swift", "SettingsViewSupport.swift",
    "SnapAIApp.swift", "SnapAIUI.swift", "WindowCoordinator.swift", "main.swift"
)
forbidden_imports = {"SnapAILogic", "SwiftUI", "UniformTypeIdentifiers", "WebKit", "PDFKit", "Quartz"}
import_pattern = re.compile(
    r"^\s*(?:@[\w.]+(?:\([^\n]*?\))?\s+)*(?:(?:public|package|internal|private|fileprivate)\s+)?"
    r"import\s+(?:(?:struct|class|enum|protocol|func|var|let|typealias)\s+)?(\w+)", re.M
)
for source in sources:
    if any(fnmatch.fnmatch(source.name, pattern) for pattern in forbidden_files):
        errors.append(f"UI source belongs in the app target: {source.name}")
    if (app / source.name).exists():
        errors.append(f"core source is compiled by both targets: {source.name}")
    for module in import_pattern.findall(source.read_text()):
        if module in forbidden_imports:
            errors.append(f"{source.name} imports forbidden module {module}")

declaration_pattern = re.compile(
    r"^(?:(?:public|package|internal|final|indirect|nonisolated)\s+)*"
    r"(?:struct|class|enum|protocol|actor|typealias)\s+(\w+)", re.M
)
def declarations(directory):
    result = defaultdict(list)
    for source in directory.glob("*.swift"):
        for name in declaration_pattern.findall(source.read_text()):
            result[name].append(source.name)
    return result

logic_types = declarations(logic)
app_types = declarations(app)
for name in sorted(logic_types.keys() & app_types.keys()):
    errors.append(f"duplicate app/core type {name}: {app_types[name]} and {logic_types[name]}")
for source in app.glob("*.swift"):
    if re.search(r"@testable\s+import\s+SnapAILogic\b", source.read_text()):
        errors.append(f"production app must use package access, not @testable: {source.name}")

if errors:
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    raise SystemExit(1)
print(f"SnapAILogic boundaries verified: {len(sources)} real sources, zero symlinks, zero duplicate app/core types.")
PY
