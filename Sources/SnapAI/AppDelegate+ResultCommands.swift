import AppKit

@MainActor
extension AppDelegate {
    @objc func copyResultFromMenu(_ sender: Any?) {
        copyResult()
    }

    func copyResult() {
        resultVM.copyOutput()
    }

    @objc func copyConversationMarkdownFromMenu(_ sender: Any?) {
        copyConversationMarkdown()
    }

    func copyConversationMarkdown() {
        resultVM.copyConversationMarkdown()
    }

    @objc func copyRequestDiagnosticsFromMenu(_ sender: Any?) {
        copyRequestDiagnostics()
    }

    func copyRequestDiagnostics() {
        resultVM.copyRequestDiagnostics()
    }

    @objc func copyBriefRequestDiagnosticsFromMenu(_ sender: Any?) {
        copyBriefRequestDiagnostics()
    }

    func copyBriefRequestDiagnostics() {
        resultVM.copyBriefRequestDiagnostics()
    }

    @objc func openAISettingsFromResultMenu(_ sender: Any?) {
        openAISettingsFromResult()
    }

    func openAISettingsFromResult() {
        showSettings(section: .ai)
    }

    @objc func replaceResultFromMenu(_ sender: Any?) {
        replaceResult()
    }

    func replaceResult() {
        resultVM.replaceOriginal()
    }

    @objc func appendResultFromMenu(_ sender: Any?) {
        appendResult()
    }

    func appendResult() {
        resultVM.appendToDocument()
    }

    @objc func exportResultFromMenu(_ sender: Any?) {
        exportResult()
    }

    func exportResult() {
        resultVM.exportConversation()
    }

    @objc func regenerateResultFromMenu(_ sender: Any?) {
        regenerateResult()
    }

    func regenerateResult() {
        resultVM.regenerate()
    }

    @objc func stopResultFromMenu(_ sender: Any?) {
        stopResult()
    }

    func stopResult() {
        resultVM.cancel()
    }

    @objc func togglePinResultFromMenu(_ sender: Any?) {
        togglePinResult()
    }

    func togglePinResult() {
        resultVM.isPinned.toggle()
        panelController.show()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let selector = menuItem.action,
           let action = resultCommandAction(for: selector) {
            let state = resultCommandState
            menuItem.title = ResultCommandFactory.menuTitle(for: action, in: state)
            menuItem.toolTip = ResultCommandFactory.menuToolTip(for: action, in: state)
            return ResultCommandFactory.isEnabled(action, in: state)
        }
        switch menuItem.action {
        case #selector(togglePinResultFromMenu(_:)):
            menuItem.title = ResultPinCommand.title(isPinned: resultVM.isPinned)
            return true
        case #selector(undoLastWriteBackFromMenu(_:)):
            return lastWriteBackRecord?.isUndoAvailable == true
        default:
            return true
        }
    }

    var resultCommandState: ResultCommandState {
        ResultCommandState(resultText: resultVM.completeText,
                           diagnosticsText: resultVM.requestDiagnosticText,
                           isStreaming: resultVM.isStreaming,
                           sourceText: resultVM.sourceText,
                           protectsContentExport: resultVM.contentExportProtectionEnabled,
                           recoveryCode: resultVM.errorRecoveryCode)
    }

    func resultCommandAction(for selector: Selector) -> ResultCommandAction? {
        ResultCommandFactory.menuDescriptors()
            .first { self.selector(for: $0.action) == selector }?
            .action
    }
}
