#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
  echo "error: $1" >&2
  exit 1
}

require_match() {
  local label="$1"
  local pattern="$2"
  local path="$3"

  if ! rg -q "$pattern" "$path"; then
    fail "$label check failed: pattern not found in $path"
  fi
}

require_no_match() {
  local label="$1"
  local pattern="$2"
  local path="$3"

  if rg -q "$pattern" "$path"; then
    fail "$label check failed: forbidden pattern found in $path"
  fi
}

require_line_count_at_most() {
  local label="$1"
  local path="$2"
  local max_lines="$3"
  local actual

  actual=$(wc -l < "$path" | tr -d ' ')
  if [ "$actual" -gt "$max_lines" ]; then
    fail "$label check failed: $path has $actual lines, expected at most $max_lines"
  fi
}

grep -Eq 'uses: actions/checkout@[0-9a-f]{40}$' .github/workflows/ci.yml \
  || fail "CI checkout action must stay pinned to an immutable commit SHA"

require_no_match "release optimization" 'unsafeFlags' Package.swift

require_match "local secret store" 'LocalSecretStore' Sources/SnapAI/SettingsPersistence.swift
require_match "local secret store tests" 'testLocalSecretStoreEncryptsProviderKeysAtRest' Tests/SnapAILogicTests/SettingsMigrationTests.swift

require_match "prompt/privacy eval corpus" 'testPromptPrivacyEvalCorpusKeepsInjectionInUserPayloadAndRedactsSecrets' Tests/SnapAILogicTests/PrivacyTests.swift
require_match "fallback eval corpus" 'testPromptPrivacyFallbackEvalCorpus' Tests/SnapAILogicTests

require_match "result command consistency tests" 'testResultCommandFactoryKeepsMenuShortcutsAndVisibleActionsConsistent' Tests/SnapAILogicTests/CommandPaletteTests.swift

require_match "macOS hotkey handler dispatch smoke" 'Hotkey handler dispatch probe' scripts/run-macos-smoke-tests.sh
require_match "app launch smoke preflight" 'scripts/run-app-launch-smoke.sh SnapAI.app' scripts/preflight-release.sh

require_match "supply-chain preflight" 'scripts/run-supply-chain-scan.sh' scripts/preflight-release.sh
require_match "SBOM packaging" 'snapai-sbom' scripts/package-release.sh
require_match "SBOM manifest verification" 'SBOM sha256' scripts/preflight-release.sh

require_line_count_at_most "SettingsView split" Sources/SnapAI/SettingsView.swift 800
require_line_count_at_most "Settings split" Sources/SnapAI/Settings.swift 900

scripts/check-logic-symlinks.sh >/dev/null
[ -x scripts/report-logic-migration-candidates.sh ] \
  || fail "SnapAILogic migration candidate analyzer must stay executable"
scripts/report-logic-migration-candidates.sh >/dev/null

[ -f Sources/SnapAILogic/ResultRouteStatusText.swift ] \
  || fail "SnapAILogic migrated ResultRouteStatusText source is missing"
[ ! -L Sources/SnapAILogic/ResultRouteStatusText.swift ] \
  || fail "SnapAILogic migrated ResultRouteStatusText must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/ResultRouteStatusText.swift ] \
  || fail "ResultRouteStatusText must not be duplicated in the app target"
[ -f Sources/SnapAILogic/TextDiff.swift ] \
  || fail "SnapAILogic migrated TextDiff source is missing"
[ ! -L Sources/SnapAILogic/TextDiff.swift ] \
  || fail "SnapAILogic migrated TextDiff must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/TextDiff.swift ] \
  || fail "TextDiff must not be duplicated in the app target"
[ -f Sources/SnapAILogic/FollowUpInputBehavior.swift ] \
  || fail "SnapAILogic migrated FollowUpInputBehavior source is missing"
[ ! -L Sources/SnapAILogic/FollowUpInputBehavior.swift ] \
  || fail "SnapAILogic migrated FollowUpInputBehavior must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/FollowUpInputBehavior.swift ] \
  || fail "FollowUpInputBehavior must not be duplicated in the app target"
[ -f Sources/SnapAILogic/FollowUpHistoryStore.swift ] \
  || fail "SnapAILogic migrated FollowUpHistoryStore source is missing"
[ ! -L Sources/SnapAILogic/FollowUpHistoryStore.swift ] \
  || fail "SnapAILogic migrated FollowUpHistoryStore must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/FollowUpHistoryStore.swift ] \
  || fail "FollowUpHistoryStore must not be duplicated in the app target"
[ -f Sources/SnapAILogic/ScreenCapturePermission.swift ] \
  || fail "SnapAILogic migrated ScreenCapturePermission source is missing"
[ ! -L Sources/SnapAILogic/ScreenCapturePermission.swift ] \
  || fail "SnapAILogic migrated ScreenCapturePermission must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/ScreenCapturePermission.swift ] \
  || fail "ScreenCapturePermission must not be duplicated in the app target"
[ -f Sources/SnapAILogic/ScreenCaptureTemporaryFile.swift ] \
  || fail "SnapAILogic migrated ScreenCaptureTemporaryFile source is missing"
[ ! -L Sources/SnapAILogic/ScreenCaptureTemporaryFile.swift ] \
  || fail "SnapAILogic migrated ScreenCaptureTemporaryFile must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/ScreenCaptureTemporaryFile.swift ] \
  || fail "ScreenCaptureTemporaryFile must not be duplicated in the app target"
[ -f Sources/SnapAILogic/ScreenCaptureFailureDiagnostic.swift ] \
  || fail "SnapAILogic migrated ScreenCaptureFailureDiagnostic source is missing"
[ ! -L Sources/SnapAILogic/ScreenCaptureFailureDiagnostic.swift ] \
  || fail "SnapAILogic migrated ScreenCaptureFailureDiagnostic must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/ScreenCaptureFailureDiagnostic.swift ] \
  || fail "ScreenCaptureFailureDiagnostic must not be duplicated in the app target"
[ -f Sources/SnapAILogic/StreamingAccumulator.swift ] \
  || fail "SnapAILogic migrated StreamingAccumulator source is missing"
[ ! -L Sources/SnapAILogic/StreamingAccumulator.swift ] \
  || fail "SnapAILogic migrated StreamingAccumulator must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/StreamingAccumulator.swift ] \
  || fail "StreamingAccumulator must not be duplicated in the app target"
[ -f Sources/SnapAILogic/SystemPrivacySettings.swift ] \
  || fail "SnapAILogic migrated SystemPrivacySettings source is missing"
[ ! -L Sources/SnapAILogic/SystemPrivacySettings.swift ] \
  || fail "SnapAILogic migrated SystemPrivacySettings must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/SystemPrivacySettings.swift ] \
  || fail "SystemPrivacySettings must not be duplicated in the app target"
[ -f Sources/SnapAILogic/TextCaptureRecoveryGuide.swift ] \
  || fail "SnapAILogic migrated TextCaptureRecoveryGuide source is missing"
[ ! -L Sources/SnapAILogic/TextCaptureRecoveryGuide.swift ] \
  || fail "SnapAILogic migrated TextCaptureRecoveryGuide must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/TextCaptureRecoveryGuide.swift ] \
  || fail "TextCaptureRecoveryGuide must not be duplicated in the app target"
[ -f Sources/SnapAILogic/SettingsWindowPinCommand.swift ] \
  || fail "SnapAILogic migrated SettingsWindowPinCommand source is missing"
[ ! -L Sources/SnapAILogic/SettingsWindowPinCommand.swift ] \
  || fail "SnapAILogic migrated SettingsWindowPinCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/SettingsWindowPinCommand.swift ] \
  || fail "SettingsWindowPinCommand must not be duplicated in the app target"
[ -f Sources/SnapAILogic/ResultCommand.swift ] \
  || fail "SnapAILogic migrated ResultCommand source is missing"
[ ! -L Sources/SnapAILogic/ResultCommand.swift ] \
  || fail "SnapAILogic migrated ResultCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/ResultCommand.swift ] \
  || fail "ResultCommand must not be duplicated in the app target"
[ -f Sources/SnapAILogic/ResultPinCommand.swift ] \
  || fail "SnapAILogic migrated ResultPinCommand source is missing"
[ ! -L Sources/SnapAILogic/ResultPinCommand.swift ] \
  || fail "SnapAILogic migrated ResultPinCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/ResultPinCommand.swift ] \
  || fail "ResultPinCommand must not be duplicated in the app target"
[ -f Sources/SnapAILogic/ResultDiagnosticsCommand.swift ] \
  || fail "SnapAILogic migrated ResultDiagnosticsCommand source is missing"
[ ! -L Sources/SnapAILogic/ResultDiagnosticsCommand.swift ] \
  || fail "SnapAILogic migrated ResultDiagnosticsCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/ResultDiagnosticsCommand.swift ] \
  || fail "ResultDiagnosticsCommand must not be duplicated in the app target"
[ -f Sources/SnapAILogic/ResultRecoveryCommand.swift ] \
  || fail "SnapAILogic migrated ResultRecoveryCommand source is missing"
[ ! -L Sources/SnapAILogic/ResultRecoveryCommand.swift ] \
  || fail "SnapAILogic migrated ResultRecoveryCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/ResultRecoveryCommand.swift ] \
  || fail "ResultRecoveryCommand must not be duplicated in the app target"
[ -f Sources/SnapAILogic/ResultWriteBackCoordinator.swift ] \
  || fail "SnapAILogic migrated ResultWriteBackCoordinator source is missing"
[ ! -L Sources/SnapAILogic/ResultWriteBackCoordinator.swift ] \
  || fail "SnapAILogic migrated ResultWriteBackCoordinator must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/ResultWriteBackCoordinator.swift ] \
  || fail "ResultWriteBackCoordinator must not be duplicated in the app target"
[ -f Sources/SnapAILogic/CommandPaletteMatcher.swift ] \
  || fail "SnapAILogic migrated CommandPaletteMatcher source is missing"
[ ! -L Sources/SnapAILogic/CommandPaletteMatcher.swift ] \
  || fail "SnapAILogic migrated CommandPaletteMatcher must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/CommandPaletteMatcher.swift ] \
  || fail "CommandPaletteMatcher must not be duplicated in the app target"
[ -f Sources/SnapAILogic/CaptureCoordinator.swift ] \
  || fail "SnapAILogic migrated CaptureCoordinator source is missing"
[ ! -L Sources/SnapAILogic/CaptureCoordinator.swift ] \
  || fail "SnapAILogic migrated CaptureCoordinator must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/CaptureCoordinator.swift ] \
  || fail "CaptureCoordinator must not be duplicated in the app target"
require_match "SnapAI app depends on SnapAILogic" 'dependencies: \["SnapAILogic"\]' Package.swift

echo "Audit remediation check: ok"
