#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

MANIFEST="scripts/logic-symlink-manifest.txt"
CURRENT=$(mktemp "${TMPDIR:-/tmp}/snapai-logic-symlinks.XXXXXX")
trap 'rm -f "$CURRENT"' EXIT

FORBIDDEN_FILE_PATTERNS=(
  "AppDelegate*.swift"
  "*View.swift"
  "*Window.swift"
  "*Panel.swift"
  "ActionSettingsSection.swift"
  "GeneralSettingsSection.swift"
  "HistorySettingsSection.swift"
  "ImportExportSettingsSection.swift"
  "PermissionSettingsSection.swift"
  "PrivacySettingsSection.swift"
  "ProviderSettingsSection.swift"
  "WorkModeSettingsSection.swift"
  "CommandPalette.swift"
  "DiffPreviewWindow.swift"
  "FloatingPanel.swift"
  "HotKeyRecorder.swift"
  "MarkdownView.swift"
  "MenuCoordinator.swift"
  "OnboardingView.swift"
  "QuickInput.swift"
  "SettingsViewSupport.swift"
  "SnapAIApp.swift"
  "SnapAIUI.swift"
  "WindowCoordinator.swift"
  "main.swift"
)

FORBIDDEN_IMPORTS=(
  "SnapAILogic"
  "SwiftUI"
  "UniformTypeIdentifiers"
  "WebKit"
  "PDFKit"
  "Quartz"
)

MAX_LOGIC_SYMLINKS=36
MIN_LOGIC_REAL_SOURCES=45

find Sources/SnapAILogic -maxdepth 1 \( -type l -o -type f \) -name '*.swift' -exec basename {} \; | sort > "$CURRENT"

if ! diff -u "$MANIFEST" "$CURRENT"; then
  echo "error: Sources/SnapAILogic symlink manifest is out of date." >&2
  echo "Add only logic-test-safe Swift files, then update $MANIFEST intentionally." >&2
  exit 1
fi

while IFS= read -r file; do
  path="Sources/SnapAILogic/$file"
  for pattern in "${FORBIDDEN_FILE_PATTERNS[@]}"; do
    if [[ "$file" == $pattern ]]; then
      echo "error: $path looks UI-only and must not enter SnapAILogic." >&2
      echo "Move shared logic into a non-UI file or keep this file in the app target only." >&2
      exit 1
    fi
  done
  if [ ! -L "$path" ]; then
    if [ ! -f "$path" ]; then
      echo "error: $path is neither a regular source file nor a symlink." >&2
      exit 1
    fi
  else
    target=$(readlink "$path")
    if [[ "$target" != ../SnapAI/*.swift ]]; then
      echo "error: $path points outside Sources/SnapAI: $target" >&2
      exit 1
    fi
    if [ ! -f "$path" ]; then
      echo "error: $path points to a missing source file: $target" >&2
      exit 1
    fi
  fi
  for module in "${FORBIDDEN_IMPORTS[@]}"; do
    if grep -Eq "^[[:space:]]*import[[:space:]]+$module([[:space:]]|$)" "$path"; then
      echo "error: $path imports $module, which is not allowed in SnapAILogic." >&2
      echo "Keep UI/rendering/document-panel code in Sources/SnapAI." >&2
      exit 1
    fi
  done
done < "$MANIFEST"

symlink_count=$(find Sources/SnapAILogic -maxdepth 1 -type l -name '*.swift' | wc -l | tr -d ' ')
real_source_count=$(find Sources/SnapAILogic -maxdepth 1 -type f -name '*.swift' | wc -l | tr -d ' ')

if [ "$symlink_count" -gt "$MAX_LOGIC_SYMLINKS" ]; then
  echo "error: Sources/SnapAILogic has $symlink_count symlink sources; expected at most $MAX_LOGIC_SYMLINKS." >&2
  echo "Migrate shared logic as real library sources instead of increasing app-source mirrors." >&2
  exit 1
fi

if [ "$real_source_count" -lt "$MIN_LOGIC_REAL_SOURCES" ]; then
  echo "error: Sources/SnapAILogic has $real_source_count real sources; expected at least $MIN_LOGIC_REAL_SOURCES." >&2
  echo "Do not regress migrated library sources back to symlinks." >&2
  exit 1
fi

echo "SnapAILogic source manifest verified ($symlink_count symlinks, $real_source_count real sources)."
