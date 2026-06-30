#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="/tmp/SnapAILogicTests"

swiftc \
  Sources/SnapAI/Action.swift \
  Sources/SnapAI/ActionCommand.swift \
  Sources/SnapAI/AutomationURLCommand.swift \
  Sources/SnapAI/Provider.swift \
  Sources/SnapAI/ModelSwitchCommand.swift \
  Sources/SnapAI/ConversationExport.swift \
  Sources/SnapAI/CommandIdentifier.swift \
  Sources/SnapAI/CommandPaletteMatcher.swift \
  Sources/SnapAI/ContextProfile.swift \
  Sources/SnapAI/SensitiveTextSanitizer.swift \
  Sources/SnapAI/MarkdownExportSafety.swift \
  Sources/SnapAI/Diagnostics.swift \
  Sources/SnapAI/InstallLogCommand.swift \
  Sources/SnapAI/History.swift \
  Sources/SnapAI/PrivacyHistoryTag.swift \
  Sources/SnapAI/HistoryExportCommand.swift \
  Sources/SnapAI/HistoryContextCommand.swift \
  Sources/SnapAI/iCloudSync.swift \
  Sources/SnapAI/Keychain.swift \
  Sources/SnapAI/LoginItem.swift \
  Sources/SnapAI/SettingsSection.swift \
  Sources/SnapAI/Settings.swift \
  Sources/SnapAI/DisplayBehaviorCommand.swift \
  Sources/SnapAI/RoutingContextCommand.swift \
  Sources/SnapAI/SettingsToggleCommand.swift \
  Sources/SnapAI/WorkModeCommand.swift \
  Sources/SnapAI/SettingsWindowPinCommand.swift \
  Sources/SnapAI/SystemPrivacySettings.swift \
  Sources/SnapAI/HotKeyUtilities.swift \
  Sources/SnapAI/PrivacyFilter.swift \
  Sources/SnapAI/PrivacySubmissionPreview.swift \
  Sources/SnapAI/FollowUpInputBehavior.swift \
  Sources/SnapAI/FollowUpHistoryStore.swift \
  Sources/SnapAI/ResultDiagnosticsCommand.swift \
  Sources/SnapAI/ResultRecoveryCommand.swift \
  Sources/SnapAI/ResultCommand.swift \
  Sources/SnapAI/ResultPinCommand.swift \
  Sources/SnapAI/ScreenCapturePermission.swift \
  Sources/SnapAI/ScreenCaptureFailureDiagnostic.swift \
  Sources/SnapAI/ScreenCaptureTemporaryFile.swift \
  Sources/SnapAI/TextCaptureRecoveryGuide.swift \
  Sources/SnapAI/TextCaptureDiagnostic.swift \
  Sources/SnapAI/TextCapture.swift \
  Sources/SnapAI/TextEditTransaction.swift \
  Sources/SnapAI/WriteBackCommand.swift \
  Sources/SnapAI/TextDiff.swift \
  Sources/SnapAI/ModelCapability.swift \
  Sources/SnapAI/AIRequestRouter.swift \
  Sources/SnapAI/AIClient.swift \
  Sources/SnapAI/UpdateChecker.swift \
  Tests/SnapAILogicTests/main.swift \
  -o "$OUT" \
  -framework AppKit \
  -framework Carbon \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -framework Security

"$OUT"
