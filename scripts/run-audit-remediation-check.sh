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
require_match "cached quick-input image preview" 'if let nsImg = model\.imagePreview' Sources/SnapAI/QuickInput.swift
require_match "bounded quick-input image optimization lifetime" 'autoreleasepool' Sources/SnapAI/QuickInput.swift
require_no_match "quick-input body image re-decode" 'if let .*model\.imageData.*NSImage\(data:' Sources/SnapAI/QuickInput.swift
require_match "settings window release lifecycle" 'func windowWillClose' Sources/SnapAI/WindowCoordinator.swift
require_match "closed window content release" 'closedWindow\.contentViewController = nil' Sources/SnapAI/WindowCoordinator.swift
require_match "settings content lazy rebuild" 'window\.contentViewController = makeSettingsContentController\(\)' Sources/SnapAI/WindowCoordinator.swift
require_no_match "unsafe AppKit automatic release" 'window\.isReleasedWhenClosed = true' Sources/SnapAI/WindowCoordinator.swift
require_match "routing metrics background persistence" 'persistenceQueue\.asyncAfter' Sources/SnapAI/RoutingMetrics.swift
require_match "routing metrics termination flush" 'RoutingMetricsStore\.shared\.flushPersistence\(\)' Sources/SnapAI/AppDelegate.swift
require_match "routing metrics coalescing tests" 'testRoutingMetricsStoreCoalescesBackgroundPersistenceAndFlushes' Tests/SnapAILogicTests/RoutingTests.swift
require_line_count_at_most "ResultView split" Sources/SnapAI/ResultView.swift 560
require_line_count_at_most "ResultLiveOutputView split" Sources/SnapAI/ResultLiveOutputView.swift 180
require_line_count_at_most "ResultCompletionMetricsView split" Sources/SnapAI/ResultCompletionMetricsView.swift 80
require_match "streaming result render mode" 'ResultContentRenderMode\.resolve' Sources/SnapAI/ResultLiveOutputView.swift
require_match "streaming scroll throttle" 'ResultAutoScrollPolicy\.shouldScroll' Sources/SnapAI/ResultViewModel.swift
require_match "result view uses throttled auto-scroll" 'vm\.shouldAutoScroll\(\)' Sources/SnapAI/ResultView.swift
require_match "isolated output observer" '@ObservedObject var state: ResultOutputState' Sources/SnapAI/ResultLiveOutputView.swift
require_match "isolated thinking observer" '@ObservedObject var state: ResultThinkingState' Sources/SnapAI/ResultLiveOutputView.swift
require_match "isolated action toolbar observer" '@ObservedObject var outputState: ResultOutputState' Sources/SnapAI/ResultLiveOutputView.swift
require_no_match "broad published output" '@Published var output:' Sources/SnapAI/ResultViewModel.swift
require_no_match "broad published thinking" '@Published var thinkingText:' Sources/SnapAI/ResultViewModel.swift
require_no_match "split completion metrics publication" '@Published var (elapsed|charCount):' Sources/SnapAI/ResultViewModel.swift
require_no_match "split diagnostic text publication" '@Published var requestDiagnostic(Brief)?Text:' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model SwiftUI dependency" '^import SwiftUI$' Sources/SnapAI/ResultViewModel.swift
require_match "deduplicated live output publication" 'guard self\.text != text else \{ return false \}' Sources/SnapAILogic/ResultLiveOutputState.swift
require_match "single diagnostic snapshot publication" '@Published private var diagnosticText: ResultDiagnosticTextSnapshot' Sources/SnapAI/ResultViewModel.swift
require_match "completion metrics leaf observer" '@ObservedObject var state: ResultCompletionState' Sources/SnapAI/ResultCompletionMetricsView.swift
require_match "completion metrics snapshot update" 'completionState\.replace\(with: completion\)' Sources/SnapAI/ResultViewModel.swift
require_match "completion snapshot test" 'testResultCompletionStatePublishesOneDeduplicatedSnapshot' Tests/SnapAILogicTests/WriteBackTests.swift
require_no_match "result root reads live output" 'vm\.(output|thinkingText)\b' Sources/SnapAI/ResultView.swift
require_match "live output isolation test" 'testResultLiveOutputStatesPublishIndependently' Tests/SnapAILogicTests/WriteBackTests.swift
require_no_match "streaming markdown reparse" 'if .*isStreaming.*MarkdownView|MarkdownView\(text: state\.text\).*isStreaming' Sources/SnapAI/ResultLiveOutputView.swift
require_no_match "streaming scroll animation storm" 'withAnimation\([^\n]*proxy\.scrollTo\("output"' Sources/SnapAI/ResultView.swift
[ -f Sources/SnapAILogic/ResultContentPresentation.swift ] \
  || fail "SnapAILogic ResultContentPresentation source is missing"
[ ! -L Sources/SnapAILogic/ResultContentPresentation.swift ] \
  || fail "SnapAILogic ResultContentPresentation must be a real source file"
[ ! -e Sources/SnapAI/ResultContentPresentation.swift ] \
  || fail "ResultContentPresentation must not be duplicated in the app target"
[ -f Sources/SnapAILogic/ResultLiveOutputState.swift ] \
  || fail "SnapAILogic ResultLiveOutputState source is missing"
[ ! -L Sources/SnapAILogic/ResultLiveOutputState.swift ] \
  || fail "SnapAILogic ResultLiveOutputState must be a real source file"
[ ! -e Sources/SnapAI/ResultLiveOutputState.swift ] \
  || fail "ResultLiveOutputState must not be duplicated in the app target"
require_line_count_at_most "HistoryWindow view split" Sources/SnapAI/HistoryWindow.swift 500
require_line_count_at_most "HistoryWindowModel split" Sources/SnapAI/HistoryWindowModel.swift 260
require_match "history presentation background refresh" 'refreshQueue\.async' Sources/SnapAI/HistoryWindowModel.swift
require_match "history query debounce" 'HistoryWindowRefreshPolicy\.delay' Sources/SnapAI/HistoryWindowModel.swift
require_match "history stale refresh protection" 'HistoryWindowRefreshPolicy\.shouldPublish' Sources/SnapAI/HistoryWindowModel.swift
require_match "history cached presentation" '@Published private\(set\) var presentation' Sources/SnapAI/HistoryWindowModel.swift
require_no_match "history broad settings observation" '@ObservedObject var settings: AppSettings' Sources/SnapAI/HistoryWindow.swift
require_no_match "history tag draft list invalidation" '@Published var tagDrafts' Sources/SnapAI/HistoryWindowModel.swift
require_no_match "history synchronous view search" 'private var filtered: \[HistoryEntry\]' Sources/SnapAI/HistoryWindow.swift
require_no_match "history retained context draft" 'var contextProfileDraft:' Sources/SnapAI/HistoryWindowModel.swift
require_match "history cached compact date formatter" 'static let compact: DateFormatter' Sources/SnapAI/History.swift
require_no_match "history per-row date formatter allocation" 'let f = DateFormatter\(\)' Sources/SnapAI/History.swift
[ -f Sources/SnapAILogic/HistoryWindowRefreshPolicy.swift ] \
  || fail "SnapAILogic HistoryWindowRefreshPolicy source is missing"
[ ! -L Sources/SnapAILogic/HistoryWindowRefreshPolicy.swift ] \
  || fail "SnapAILogic HistoryWindowRefreshPolicy must be a real source file"
[ ! -e Sources/SnapAI/HistoryWindowRefreshPolicy.swift ] \
  || fail "HistoryWindowRefreshPolicy must not be duplicated in the app target"

scripts/check-logic-symlinks.sh >/dev/null
[ -x scripts/report-logic-migration-candidates.sh ] \
  || fail "SnapAILogic migration candidate analyzer must stay executable"
scripts/report-logic-migration-candidates.sh >/dev/null
[ -x scripts/profile-runtime-memory.sh ] \
  || fail "runtime memory profiler must stay executable"
bash -n scripts/profile-runtime-memory.sh \
  || fail "runtime memory profiler syntax check failed"
candidate_report=$(scripts/report-logic-migration-candidates.sh)
rg -q 'app-api' <<< "$candidate_report" \
  || fail "SnapAILogic migration candidate analyzer must classify app API bridge risk"

declared_logic_tests=$(
  rg --no-filename '^func test[A-Za-z0-9_]+\(' Tests/SnapAILogicTests/*.swift \
    | sed -E 's/^func ([A-Za-z0-9_]+).*/\1/' \
    | sort -u
)
registered_logic_tests=$(
  sed -nE 's/^[[:space:]]*(test[A-Za-z0-9_]+)\(\)$/\1/p' Tests/SnapAILogicTests/main.swift \
    | sort -u
)
[ "$declared_logic_tests" = "$registered_logic_tests" ] \
  || fail "every top-level logic test must be registered in runAllLogicTests"

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
[ -f Sources/SnapAILogic/TextCaptureDiagnostic.swift ] \
  || fail "SnapAILogic migrated TextCaptureDiagnostic source is missing"
[ ! -L Sources/SnapAILogic/TextCaptureDiagnostic.swift ] \
  || fail "SnapAILogic migrated TextCaptureDiagnostic must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/TextCaptureDiagnostic.swift ] \
  || fail "TextCaptureDiagnostic must not be duplicated in the app target"
[ -f Sources/SnapAI/TextCaptureDiagnosticAppBridge.swift ] \
  || fail "TextCaptureDiagnostic app bridge is missing"
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
[ -f Sources/SnapAILogic/ResultPersistence.swift ] \
  || fail "SnapAILogic migrated ResultPersistence source is missing"
[ ! -L Sources/SnapAILogic/ResultPersistence.swift ] \
  || fail "SnapAILogic migrated ResultPersistence must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/ResultPersistence.swift ] \
  || fail "ResultPersistence must not be duplicated in the app target"
[ -f Sources/SnapAILogic/ConversationExport.swift ] \
  || fail "SnapAILogic migrated ConversationExport source is missing"
[ ! -L Sources/SnapAILogic/ConversationExport.swift ] \
  || fail "SnapAILogic migrated ConversationExport must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/ConversationExport.swift ] \
  || fail "ConversationExport must not be duplicated in the app target"
[ -f Sources/SnapAI/ResultPersistenceAppBridge.swift ] \
  || fail "ResultPersistence app bridge is missing"
[ -f Sources/SnapAILogic/AutomationRouter.swift ] \
  || fail "SnapAILogic migrated AutomationRouter source is missing"
[ ! -L Sources/SnapAILogic/AutomationRouter.swift ] \
  || fail "SnapAILogic migrated AutomationRouter must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/AutomationRouter.swift ] \
  || fail "AutomationRouter must not be duplicated in the app target"
[ -f Sources/SnapAILogic/AutomationURLCommand.swift ] \
  || fail "SnapAILogic migrated AutomationURLCommand source is missing"
[ ! -L Sources/SnapAILogic/AutomationURLCommand.swift ] \
  || fail "SnapAILogic migrated AutomationURLCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/AutomationURLCommand.swift ] \
  || fail "AutomationURLCommand must not be duplicated in the app target"
[ -f Sources/SnapAI/AutomationURLCommandAppBridge.swift ] \
  || fail "AutomationURLCommand app bridge is missing"
[ -f Sources/SnapAILogic/SettingsSection.swift ] \
  || fail "SnapAILogic migrated SettingsSection source is missing"
[ ! -L Sources/SnapAILogic/SettingsSection.swift ] \
  || fail "SnapAILogic migrated SettingsSection must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/SettingsSection.swift ] \
  || fail "SettingsSection must not be duplicated in the app target"
[ -f Sources/SnapAILogic/CommandPaletteMatcher.swift ] \
  || fail "SnapAILogic migrated CommandPaletteMatcher source is missing"
[ ! -L Sources/SnapAILogic/CommandPaletteMatcher.swift ] \
  || fail "SnapAILogic migrated CommandPaletteMatcher must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/CommandPaletteMatcher.swift ] \
  || fail "CommandPaletteMatcher must not be duplicated in the app target"
[ -f Sources/SnapAILogic/CommandIdentifier.swift ] \
  || fail "SnapAILogic migrated CommandIdentifier source is missing"
[ ! -L Sources/SnapAILogic/CommandIdentifier.swift ] \
  || fail "SnapAILogic migrated CommandIdentifier must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/CommandIdentifier.swift ] \
  || fail "CommandIdentifier must not be duplicated in the app target"
[ -f Sources/SnapAILogic/CaptureCoordinator.swift ] \
  || fail "SnapAILogic migrated CaptureCoordinator source is missing"
[ ! -L Sources/SnapAILogic/CaptureCoordinator.swift ] \
  || fail "SnapAILogic migrated CaptureCoordinator must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/CaptureCoordinator.swift ] \
  || fail "CaptureCoordinator must not be duplicated in the app target"
[ -f Sources/SnapAILogic/ActionCommand.swift ] \
  || fail "SnapAILogic migrated ActionCommand source is missing"
[ ! -L Sources/SnapAILogic/ActionCommand.swift ] \
  || fail "SnapAILogic migrated ActionCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/ActionCommand.swift ] \
  || fail "ActionCommand must not be duplicated in the app target"
[ -f Sources/SnapAILogic/DisplayBehaviorCommand.swift ] \
  || fail "SnapAILogic migrated DisplayBehaviorCommand source is missing"
[ ! -L Sources/SnapAILogic/DisplayBehaviorCommand.swift ] \
  || fail "SnapAILogic migrated DisplayBehaviorCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/DisplayBehaviorCommand.swift ] \
  || fail "DisplayBehaviorCommand must not be duplicated in the app target"
[ -f Sources/SnapAILogic/WorkModeCommand.swift ] \
  || fail "SnapAILogic migrated WorkModeCommand source is missing"
[ ! -L Sources/SnapAILogic/WorkModeCommand.swift ] \
  || fail "SnapAILogic migrated WorkModeCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/WorkModeCommand.swift ] \
  || fail "WorkModeCommand must not be duplicated in the app target"
[ -f Sources/SnapAILogic/SettingsToggleCommand.swift ] \
  || fail "SnapAILogic migrated SettingsToggleCommand source is missing"
[ ! -L Sources/SnapAILogic/SettingsToggleCommand.swift ] \
  || fail "SnapAILogic migrated SettingsToggleCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/SettingsToggleCommand.swift ] \
  || fail "SettingsToggleCommand must not be duplicated in the app target"
[ -f Sources/SnapAI/SettingsToggleCommandAppSettings.swift ] \
  || fail "SettingsToggleCommand AppSettings bridge is missing"
[ -f Sources/SnapAILogic/ModelSwitchCommand.swift ] \
  || fail "SnapAILogic migrated ModelSwitchCommand source is missing"
[ ! -L Sources/SnapAILogic/ModelSwitchCommand.swift ] \
  || fail "SnapAILogic migrated ModelSwitchCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/ModelSwitchCommand.swift ] \
  || fail "ModelSwitchCommand must not be duplicated in the app target"
[ -f Sources/SnapAILogic/RoutingContextCommand.swift ] \
  || fail "SnapAILogic migrated RoutingContextCommand source is missing"
[ ! -L Sources/SnapAILogic/RoutingContextCommand.swift ] \
  || fail "SnapAILogic migrated RoutingContextCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/RoutingContextCommand.swift ] \
  || fail "RoutingContextCommand must not be duplicated in the app target"
[ -f Sources/SnapAILogic/ActionTemplateLibrary.swift ] \
  || fail "SnapAILogic migrated ActionTemplateLibrary source is missing"
[ ! -L Sources/SnapAILogic/ActionTemplateLibrary.swift ] \
  || fail "SnapAILogic migrated ActionTemplateLibrary must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/ActionTemplateLibrary.swift ] \
  || fail "ActionTemplateLibrary must not be duplicated in the app target"
[ -f Sources/SnapAI/ActionTemplateLibraryAppBridge.swift ] \
  || fail "ActionTemplateLibrary app bridge is missing"
[ -f Sources/SnapAILogic/HistoryExportCommand.swift ] \
  || fail "SnapAILogic migrated HistoryExportCommand source is missing"
[ ! -L Sources/SnapAILogic/HistoryExportCommand.swift ] \
  || fail "SnapAILogic migrated HistoryExportCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/HistoryExportCommand.swift ] \
  || fail "HistoryExportCommand must not be duplicated in the app target"
[ -f Sources/SnapAILogic/HistoryContextCommand.swift ] \
  || fail "SnapAILogic migrated HistoryContextCommand source is missing"
[ ! -L Sources/SnapAILogic/HistoryContextCommand.swift ] \
  || fail "SnapAILogic migrated HistoryContextCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/HistoryContextCommand.swift ] \
  || fail "HistoryContextCommand must not be duplicated in the app target"
[ -f Sources/SnapAILogic/InstallLogCommand.swift ] \
  || fail "SnapAILogic migrated InstallLogCommand source is missing"
[ ! -L Sources/SnapAILogic/InstallLogCommand.swift ] \
  || fail "SnapAILogic migrated InstallLogCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/InstallLogCommand.swift ] \
  || fail "InstallLogCommand must not be duplicated in the app target"
[ -f Sources/SnapAI/InstallLogCommandAppBridge.swift ] \
  || fail "InstallLogCommand app bridge is missing"
[ -f Sources/SnapAI/HistoryExportCommandAppBridge.swift ] \
  || fail "History command app bridge is missing"
[ -f Sources/SnapAILogic/WriteBackCommand.swift ] \
  || fail "SnapAILogic migrated WriteBackCommand source is missing"
[ ! -L Sources/SnapAILogic/WriteBackCommand.swift ] \
  || fail "SnapAILogic migrated WriteBackCommand must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/WriteBackCommand.swift ] \
  || fail "WriteBackCommand must not be duplicated in the app target"
[ -f Sources/SnapAI/WriteBackCommandAppBridge.swift ] \
  || fail "WriteBackCommand app bridge is missing"
[ -f Sources/SnapAILogic/WriteBackCompatibility.swift ] \
  || fail "SnapAILogic migrated WriteBackCompatibility source is missing"
[ ! -L Sources/SnapAILogic/WriteBackCompatibility.swift ] \
  || fail "SnapAILogic migrated WriteBackCompatibility must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/WriteBackCompatibility.swift ] \
  || fail "WriteBackCompatibility must not be duplicated in the app target"
[ -f Sources/SnapAILogic/TextWriteBackLogic.swift ] \
  || fail "SnapAILogic migrated TextWriteBackLogic source is missing"
[ ! -L Sources/SnapAILogic/TextWriteBackLogic.swift ] \
  || fail "SnapAILogic migrated TextWriteBackLogic must be a real source file, not a symlink"
[ ! -e Sources/SnapAILogic/TextEditTransaction.swift ] \
  || fail "AppKit TextEditTransaction must stay out of SnapAILogic"
[ ! -e Sources/SnapAILogic/MenuCoordinator.swift ] \
  || fail "AppKit MenuCoordinator must stay out of SnapAILogic"
[ -f Sources/SnapAILogic/UpdateChecker.swift ] \
  || fail "SnapAILogic migrated UpdateChecker source is missing"
[ ! -L Sources/SnapAILogic/UpdateChecker.swift ] \
  || fail "SnapAILogic migrated UpdateChecker must be a real source file, not a symlink"
[ ! -e Sources/SnapAI/UpdateChecker.swift ] \
  || fail "mixed app/logic UpdateChecker source must not return"
[ -f Sources/SnapAI/UpdateCheckerApp.swift ] \
  || fail "UpdateChecker app adapter is missing"
require_line_count_at_most "UpdateChecker logic split" Sources/SnapAILogic/UpdateChecker.swift 650
require_line_count_at_most "UpdateChecker app split" Sources/SnapAI/UpdateCheckerApp.swift 520
require_match "SnapAI app depends on SnapAILogic" 'dependencies: \["SnapAILogic"\]' Package.swift

echo "Audit remediation check: ok"
