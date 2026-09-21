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

  if ! rg -q -- "$pattern" "$path"; then
    fail "$label check failed: pattern not found in $path"
  fi
}

require_no_match() {
  local label="$1"
  local pattern="$2"
  local path="$3"

  if rg -q -- "$pattern" "$path"; then
    fail "$label check failed: forbidden pattern found in $path"
  fi
}

grep -Eq 'uses: actions/checkout@[0-9a-f]{40}$' .github/workflows/ci.yml \
  || fail "CI checkout action must stay pinned to an immutable commit SHA"

require_no_match "release optimization" 'unsafeFlags' Package.swift

require_match "local secret store" 'LocalSecretStore' Sources/SnapAILogic/SettingsPersistence.swift
require_match "local secret store tests" 'testLocalSecretStoreEncryptsProviderKeysAtRest' Tests/SnapAILogicTests/SettingsMigrationTests.swift

require_match "prompt/privacy eval corpus" 'testPromptPrivacyEvalCorpusKeepsInjectionInUserPayloadAndRedactsSecrets' Tests/SnapAILogicTests/PrivacyTests.swift
require_match "fallback eval corpus" 'testPromptPrivacyFallbackEvalCorpus' Tests/SnapAILogicTests

require_match "result command consistency tests" 'testResultCommandFactoryKeepsMenuShortcutsAndVisibleActionsConsistent' Tests/SnapAILogicTests/CommandPaletteTests.swift

require_match "macOS hotkey handler dispatch smoke" 'Hotkey handler dispatch probe' scripts/run-macos-smoke-tests.sh
require_match "app launch smoke preflight" 'scripts/run-app-launch-smoke.sh SnapAI.app' scripts/preflight-release.sh
require_match "SwiftUI toolchain preflight" 'source scripts/configure-swift-toolchain\.sh' build.sh
require_match "release SwiftUI toolchain preflight" 'source scripts/configure-swift-toolchain\.sh' scripts/preflight-release.sh
require_match "reduced-motion panel presentation" 'accessibilityDisplayShouldReduceMotion' Sources/SnapAI/FloatingPanel.swift
require_match "reduced-motion streaming UI" 'accessibilityReduceMotion' Sources/SnapAI/SnapAIUI.swift
require_match "cancellable transient UI state" 'SnapAITransientState' Sources/SnapAI/SnapAIUI.swift
require_no_match "uncancellable settings notice" 'asyncAfter.*(actionLibraryNotice|configNotice|copyNotice)' Sources/SnapAI

require_match "supply-chain preflight" 'scripts/run-supply-chain-scan.sh' scripts/preflight-release.sh
require_match "SBOM packaging" 'snapai-sbom' scripts/package-release.sh
require_match "SBOM manifest verification" 'SBOM sha256' scripts/preflight-release.sh

require_match "cached quick-input image preview" 'model\.imagePreview' Sources/SnapAI/QuickInputView.swift
require_match "bounded quick-input image optimization lifetime" 'autoreleasepool' Sources/SnapAI/QuickInput.swift
require_no_match "quick-input body image re-decode" 'if let .*model\.imageData.*NSImage\(data:' Sources/SnapAI/QuickInput.swift
require_match "settings window release lifecycle" 'func windowWillClose' Sources/SnapAI/WindowCoordinator.swift
require_match "closed window content release" 'closedWindow\.contentViewController = nil' Sources/SnapAI/WindowCoordinator.swift
require_match "settings content lazy rebuild" 'window\.contentViewController = makeSettingsContentController\(\)' Sources/SnapAI/WindowCoordinator.swift
require_no_match "unsafe AppKit automatic release" 'window\.isReleasedWhenClosed = true' Sources/SnapAI/WindowCoordinator.swift
require_match "routing metrics background persistence" 'persistenceQueue\.asyncAfter' Sources/SnapAILogic/RoutingMetrics.swift
require_match "routing metrics termination flush" 'RoutingMetricsStore\.shared\.flushPersistence\(\)' Sources/SnapAI/AppDelegate.swift
require_match "routing metrics coalescing tests" 'testRoutingMetricsStoreCoalescesBackgroundPersistenceAndFlushes' Tests/SnapAILogicTests/RoutingTests.swift
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
require_match "incremental live output publication" 'self\.text\.append\(contentsOf: text\)' Sources/SnapAILogic/ResultLiveOutputState.swift
require_match "single diagnostic snapshot publication" '@Published private var diagnosticText: ResultDiagnosticTextSnapshot' Sources/SnapAI/ResultViewModel.swift
require_match "completion metrics leaf observer" '@ObservedObject var state: ResultCompletionState' Sources/SnapAI/ResultCompletionMetricsView.swift
require_match "completion metrics snapshot update" 'state\.replace\(with: metrics\)' Sources/SnapAI/ResultCompletionCoordinator.swift
require_match "completion snapshot test" 'testResultCompletionStatePublishesOneDeduplicatedSnapshot' Tests/SnapAILogicTests/WriteBackTests.swift
require_match "completion lifecycle test" 'testResultCompletionLifecycleRunsOnceAndResetsCleanly' Tests/SnapAILogicTests/WriteBackTests.swift
require_match "completion coordinator usage" 'completionCoordinator\.finish' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model completion flags" 'private var (startTime|savedToHistory|metricsFinished)' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model history persistence" 'ResultPersistence\.saveHistoryIfNeeded' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model usage persistence" 'settings\.recordActionUsage' Sources/SnapAI/ResultViewModel.swift
require_match "route attempt coordinator usage" 'routeAttemptCoordinator\.prepare' Sources/SnapAI/ResultViewModel.swift
require_match "single success elapsed sample" 'let elapsedMilliseconds = AIRequestAttemptDiagnostic\.elapsedMilliseconds' Sources/SnapAI/ResultRouteAttemptCoordinator.swift
require_no_match "result view model route scoped settings" 'AIRequestRouter\.scopedSettings' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model route fallback decision" 'FallbackRunner\.routeFailure' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model route metrics write" 'RoutingMetricsStore\.shared\.record(Success|Failure)' Sources/SnapAI/ResultViewModel.swift
require_match "request preparation coordinator usage" 'requestPreparationCoordinator\.prepare' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model context diagnostics" 'AIRequestContextDiagnostic\.make' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model payload diagnostics" 'AIRequestPayloadDiagnostic\.make' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model pipeline diagnostics" 'ActionPipelineDiagnostic\.make' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model route candidates" 'AIRequestRouter\.candidates' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model payload counts" 'RequestSession\.payloadCharacterCounts' Sources/SnapAI/ResultViewModel.swift
require_match "streaming coordinator usage" 'streamingCoordinator\.begin' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model streaming lifecycle state" 'private var (streamAccumulator|streamDone|typewriterTimer|typewriterBuffer)' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model typewriter task per tick" 'Task \{ @MainActor.*tick' Sources/SnapAI/ResultViewModel.swift
require_no_match "full output replacement on provider delta" 'self\.output = immediate' Sources/SnapAI/ResultViewModel.swift
require_no_match "typewriter timer task allocation" 'Task[[:space:]]*\{' Sources/SnapAI/ResultStreamingCoordinator.swift
require_match "streaming lifecycle test" 'testResultStreamingLifecycleCoordinatesImmediateAndTypewriterPresentation' Tests/SnapAILogicTests/RoutingTests.swift
require_match "submission coordinator usage" 'submissionCoordinator\.prepare' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model conversation storage" 'private var history: \[ChatMessage\]' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model pending image retention" 'pendingImage(Data|MimeType)' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model privacy fallback duplication" 'PrivacyRiskAssessment\.assess' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model request session assembly" 'RequestSession\.' Sources/SnapAI/ResultViewModel.swift
require_match "passthrough privacy regression test" 'testPrivacyPreparedSubmissionPassthroughPreservesRiskProtection' Tests/SnapAILogicTests/PrivacyTests.swift
require_match "result operation coordinator usage" 'operationCoordinator\.copy' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model pasteboard mutation" 'NSPasteboard|clearContents\(\)|setString\(' Sources/SnapAI/ResultViewModel.swift
require_no_match "result view model save panel" 'NSSavePanel|allowedContentTypes|runModal\(\)' Sources/SnapAI/ResultViewModel.swift
require_no_match "silent conversation export failure in view model" 'try\?.*\.write\(' Sources/SnapAI/ResultViewModel.swift
require_no_match "silent conversation export failure in coordinator" 'try\?.*\.write\(' Sources/SnapAI/ResultOperationCoordinator.swift
require_match "isolated result operation feedback observer" '@ObservedObject var coordinator: ResultOperationCoordinator' Sources/SnapAI/ResultOperationFeedbackView.swift
require_match "isolated result operation feedback publication" '@Published private\(set\) var feedback: ResultOperationFeedback\?' Sources/SnapAI/ResultOperationCoordinator.swift
require_no_match "broad result operation feedback publication" '@Published.*operationFeedback' Sources/SnapAI/ResultViewModel.swift
require_match "result operation feedback regression test" 'testResultOperationFeedbackAndExportFilenameAreActionable' Tests/SnapAILogicTests/WriteBackTests.swift
require_no_match "result root reads live output" 'vm\.(output|thinkingText)\b' Sources/SnapAI/ResultView.swift
require_match "live output isolation test" 'testResultLiveOutputStatesPublishIndependently' Tests/SnapAILogicTests/WriteBackTests.swift
require_no_match "streaming markdown reparse" 'if .*isStreaming.*MarkdownView|MarkdownView\(text: state\.text\).*isStreaming' Sources/SnapAI/ResultLiveOutputView.swift
require_no_match "markdown parsing in SwiftUI body" 'MarkdownParser\.parse|AttributedString\(markdown:' Sources/SnapAI/MarkdownView.swift
require_match "markdown background presentation refresh" 'refreshQueue\.async' Sources/SnapAI/MarkdownPresentationModel.swift
require_match "markdown ready final scroll" 'onPresentationReady: onMarkdownReady' Sources/SnapAI/ResultLiveOutputView.swift
require_match "markdown code copy feedback route" 'onCopyCode: onCopyCode' Sources/SnapAI/ResultLiveOutputView.swift
require_no_match "markdown direct pasteboard mutation" 'NSPasteboard|clearContents\(\)|setString\(' Sources/SnapAI/MarkdownView.swift
require_match "markdown presentation regression test" 'testMarkdownPresentationBuildsBlocksAndRejectsStaleRefreshes' Tests/SnapAILogicTests/WriteBackTests.swift
require_no_match "streaming scroll animation storm" 'withAnimation\([^\n]*proxy\.scrollTo\("output"' Sources/SnapAI/ResultView.swift

scripts/check-logic-symlinks.sh

for bridge in TextCaptureDiagnosticAppBridge ResultPersistenceAppBridge SettingsToggleCommandAppSettings ActionTemplateLibraryAppBridge HistoryExportCommandAppBridge WriteBackCommandAppBridge UpdateCheckerApp; do
  test -f "Sources/SnapAI/$bridge.swift" || fail "Missing app adapter: $bridge"
done

require_match "SnapAI app depends on SnapAILogic" 'dependencies: \["SnapAILogic"\]' Package.swift
require_match "SwiftPM release build" 'swift build -c' build.sh
require_match "declared minimum macOS" '\.macOS\(\.v14\)' Package.swift
require_match "release manifest matches trusted key" 'verify_manifest_signature.*Contents/Resources/ManifestPublicKey.pem' scripts/package-release.sh
require_match "stream runtime gate" 'run-streaming-runtime-tests.sh' scripts/preflight-release.sh
require_match "app runtime gate" 'run-app-runtime-tests.sh' scripts/preflight-release.sh
require_match "native deployment gate" 'validate_binary_deployment' scripts/preflight-release.sh
require_match "latest request callback ownership" 'self.requestID == requestID' Sources/SnapAI/ResultViewModel.swift
require_match "reopened panel ownership" 'panel.presentationID == presentationID' Sources/SnapAI/FloatingPanel.swift
require_match "settings terminate flush" 'settings.save\(\)' Sources/SnapAI/AppDelegate.swift
require_no_match "UI render flush side effects" 'vm\.completeText' Sources/SnapAI/ResultView.swift

for regression in testServerSentEventParserPreservesFramingAndUnicode testAIStreamDecoderDetectsIncompleteAndLimitedResponses testHistoryStoreMigrationAndIndexTransactions testHistoryStoreConnectionRecoveryAndConcurrency testSettingsPersistenceRecoveryAndValidation testLocalSecretStoreConcurrentWritesAndRecovery; do
  require_match "registered regression: $regression" "$regression\(\)" Tests/SnapAILogicTests/main.swift
done

test -f LICENSE || fail "MIT license file LICENSE is missing"
require_match "license referenced by README" '\[MIT License\]\(LICENSE\)' README.md
require_match "cancel saves tagged partial history" 'additionalHistoryTags: completeText.isEmpty' Sources/SnapAI/ResultViewModel.swift
require_match "partial result history tag" 'partialResult = "部分结果"' Sources/SnapAILogic/PrivacyHistoryTag.swift
require_match "runTool timeout" 'timeout: TimeInterval = 30' Sources/SnapAILogic/UpdateChecker.swift
require_match "history store file permissions" 'posixPermissions: 0o600' Sources/SnapAILogic/HistoryStore.swift
require_match "slow-gap timeout probe" 'testStreamIdleGapWithinRequestTimeout' Tests/Runtime/StreamingRuntimeSmoke.swift
require_match "liquid glass card helper" 'func snapAIGlassCard' Sources/SnapAI/SnapAILiquidGlass.swift
require_match "liquid glass field helper" 'func snapAIGlassField' Sources/SnapAI/SnapAILiquidGlass.swift
require_match "liquid glass pill helper" 'func snapAIGlassPill' Sources/SnapAI/SnapAILiquidGlass.swift
require_match "chrome transparency helper" 'func snapAIChrome' Sources/SnapAI/SnapAILiquidGlass.swift
require_match "scroll edge helper" 'func snapAIScrollEdge' Sources/SnapAI/SnapAILiquidGlass.swift
require_match "glass toolbar group" 'struct SnapAIGlassToolbarGroup' Sources/SnapAI/SnapAILiquidGlass.swift
require_no_match "legacy opaque card surface" '\.snapAISurface\(' Sources/SnapAI
require_no_match "legacy chrome color block" 'Surface\.chrome' Sources/SnapAI
require_no_match "legacy material fallback" 'regularMaterial' Sources/SnapAI
require_match "endpoint host display helper" 'var displayHost' Sources/SnapAILogic/Provider.swift
require_match "endpoint host regression" 'testProviderDisplayHostShowsOnlyHost\(\)' Tests/SnapAILogicTests/main.swift
require_match "app runtime gate in CI" 'run-app-runtime-tests.sh' .github/workflows/ci.yml

echo "Audit remediation check: ok"
