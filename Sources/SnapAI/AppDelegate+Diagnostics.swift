import AppKit
import SnapAILogic

@MainActor
extension AppDelegate {
    @objc func openCommandPaletteFromMenu(_ sender: Any?) {
        openCommandPalette()
    }

    @objc func openCommandPalette() {
        commandPalette.show()
    }

    @objc func openHistoryWindowFromMenu(_ sender: Any?) {
        openHistoryWindow()
    }

    @objc func openHistoryWindow() {
        historyWindow.show()
    }

    @objc func openPermissionHealthFromMenu(_ sender: Any?) {
        openPermissionHealth()
    }

    @objc func openPermissionHealth() {
        permissionHealth.show()
    }

    func copyPermissionDiagnostics() {
        copyPermissionDiagnostics(full: true)
    }

    func copyBriefPermissionDiagnostics() {
        copyPermissionDiagnostics(full: false)
    }

    func currentPermissionHealthSnapshot() -> PermissionHealthSnapshot {
        currentPermissionHealthSnapshot(includeSigningSummary: true)
    }

    func currentPermissionHealthSnapshot(includeSigningSummary: Bool) -> PermissionHealthSnapshot {
        PermissionHealthSnapshot.make(
            settings: settings,
            hotKeyFailures: hotKeyRegistrationFailures,
            textCaptureStatus: currentTextCaptureStatusSummary() ?? "none",
            writeBackStatus: currentWriteBackStatusSummary() ?? "none",
            recentAIRequestStatus: resultVM?.requestHealthStatusText ?? "none",
            installLogStatus: UpdateChecker.latestInstallLogStatus().permissionHealthStatus,
            includeSigningSummary: includeSigningSummary
        )
    }

    func copyPermissionDiagnostics(full: Bool) {
        let snapshot = currentPermissionHealthSnapshot()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full ? snapshot.diagnosticText : snapshot.briefDiagnosticText, forType: .string)
    }

    @objc func copyPermissionRecoverySuggestionsFromMenu(_ sender: Any?) {
        copyPermissionRecoverySuggestions()
    }

    func copyPermissionRecoverySuggestions() {
        let snapshot = currentPermissionHealthSnapshot(includeSigningSummary: false)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot.recoverySuggestionClipboardText, forType: .string)
    }

    func revealLatestInstallLog() {
        guard let url = UpdateChecker.latestInstallLogURL() else {
            openPermissionHealth()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyLatestInstallLogPath() {
        guard let url = UpdateChecker.latestInstallLogURL() else {
            openPermissionHealth()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    func toggleSettingsWindowPinnedFromCommandPalette() {
        windowCoordinator.toggleSettingsWindowPinnedAndShow()
    }
}
