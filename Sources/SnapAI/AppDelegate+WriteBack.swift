import AppKit

@MainActor
extension AppDelegate {
    /// 把结果替换回原文位置(#3)
    func replaceSelection(original: String, with replacement: String) {
        defer {
            previousSelectionSnapshot = nil
            TextCapture.clearRecentSelectionSnapshot()
        }
        let decision = DiffPreviewWindowController.present(original: original,
                                                           revised: replacement,
                                                           actionName: resultVM.action.name)
        switch decision {
        case .replace:
            guard let writeBackTarget = validatedWriteBackTarget() else {
                copyWriteBackFallback(text: replacement,
                                      operation: .replace,
                                      originalCharacterCount: original.count,
                                      title: "无法自动替换",
                                      reason: writeBackTargetUnavailableReason())
                return
            }
            panelController.hide()
            TextEditTransaction(targetApp: writeBackTarget,
                                selectionSnapshot: previousSelectionSnapshot)
                .replace(original: original, with: replacement) { [weak self] in
                    self?.recordWriteBack(targetApp: writeBackTarget,
                                          original: original,
                                          replacement: replacement)
                } failure: { [weak self] snapshot in
                    self?.handleUnsafePasteboardWriteBack(operation: .replace,
                                                         originalCharacterCount: original.count,
                                                         payloadCharacterCount: replacement.count,
                                                         snapshot: snapshot)
                }
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(replacement, forType: .string)
        case .cancel:
            break
        }
    }

    /// 把结果追加到光标后(#8):先发 → 键移到选区末尾,再粘贴 "\n" + result
    func appendSelection(with text: String) {
        guard let writeBackTarget = validatedWriteBackTarget() else {
            copyWriteBackFallback(text: text,
                                  operation: .append,
                                  originalCharacterCount: 0,
                                  title: "无法自动追加",
                                  reason: writeBackTargetUnavailableReason())
            return
        }
        let insertedText = TextWriteBackPayload.appendPayload(for: text)
        TextEditTransaction(targetApp: writeBackTarget).append(text) { [weak self] in
            self?.recordWriteBack(targetApp: writeBackTarget,
                                  operation: .append,
                                  original: "",
                                  replacement: insertedText)
        } failure: { [weak self] snapshot in
            self?.handleUnsafePasteboardWriteBack(operation: .append,
                                                 originalCharacterCount: 0,
                                                 payloadCharacterCount: insertedText.count,
                                                 snapshot: snapshot)
        }
    }

    func validatedWriteBackTarget() -> NSRunningApplication? {
        guard let target = previousApp,
              !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return target
    }

    func writeBackTargetUnavailableReason() -> String {
        guard let target = previousApp else {
            return "没有可信的原应用目标。"
        }
        let appName = MarkdownExportSafety.metadata(target.localizedName,
                                                    fallback: "原应用",
                                                    maxLength: 80)
        if target.isTerminated {
            return "\(appName) 已退出。"
        }
        if target.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return "当前目标是 SnapAI 自身。"
        }
        return "\(appName) 暂不可用。"
    }

    func copyWriteBackFallback(text: String,
                                       operation: TextWriteBackOperation,
                                       originalCharacterCount: Int,
                                       title: String,
                                       reason: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let diagnostic = TextWriteBackFallbackDiagnostic(operation: operation,
                                                         targetApp: previousApp,
                                                         reason: reason,
                                                         copiedToPasteboard: true,
                                                         originalCharacterCount: originalCharacterCount,
                                                         payloadCharacterCount: text.count)
        lastWriteBackStatusSummary = diagnostic.diagnosticSummary
        presentWriteBackNotice(title: title,
                               message: diagnostic.noticeMessage,
                               showsDiagnosticsButton: true)
    }

    func handleUnsafePasteboardWriteBack(operation: TextWriteBackOperation,
                                                 originalCharacterCount: Int,
                                                 payloadCharacterCount: Int,
                                                 snapshot: PasteboardSnapshot) {
        let diagnostic = TextWriteBackFallbackDiagnostic(operation: operation,
                                                         targetApp: previousApp,
                                                         reason: "\(snapshot.recoveryMessage) reason=\(snapshot.reasonCode), bytes=\(snapshot.totalByteCount), items=\(snapshot.itemCount), types=\(snapshot.typeCount)",
                                                         copiedToPasteboard: false,
                                                         originalCharacterCount: originalCharacterCount,
                                                         payloadCharacterCount: payloadCharacterCount,
                                                         recoveryOverride: snapshot.recoveryMessage)
        lastWriteBackStatusSummary = diagnostic.diagnosticSummary
        presentWriteBackNotice(title: "已取消自动写回",
                               message: diagnostic.noticeMessage,
                               showsDiagnosticsButton: true)
    }

    func presentWriteBackNotice(title: String,
                                        message: String,
                                        showsDiagnosticsButton: Bool = false) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        if showsDiagnosticsButton {
            alert.addButton(withTitle: "打开权限健康中心")
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn,
           showsDiagnosticsButton {
            openPermissionHealth()
        }
    }

    func recordWriteBack(targetApp: NSRunningApplication?,
                                 operation: TextWriteBackOperation = .replace,
                                 original: String,
                                 replacement: String) {
        lastWriteBackRecord = TextWriteBackRecord(targetApp: targetApp,
                                                  operation: operation,
                                                  originalText: original,
                                                  replacementText: replacement)
        lastWriteBackStatusSummary = lastWriteBackRecord?.diagnosticSummary
        buildMenu()
        installMainMenu()
    }

    func currentWriteBackStatusSummary() -> String? {
        WriteBackCommandFactory.statusSummary(for: lastWriteBackRecord,
                                              fallback: lastWriteBackStatusSummary)
    }

    func recordTextCaptureOutcome(_ outcome: TextCaptureOutcome) {
        let characterCount = outcome.usableText?.count ?? 0
        let diagnostic = characterCount > 0
            ? TextCaptureDiagnostic.captured(accessibilityGranted: TextCapture.hasAccessibilityPermission(),
                                             preferAX: settings.useAXFirst,
                                             frontmostAppName: previousApp?.localizedName,
                                             characterCount: characterCount,
                                             method: outcome.method,
                                             clipboardWaitAttempts: outcome.clipboardWaitAttempts)
            : TextCaptureDiagnostic.noSelection(accessibilityGranted: TextCapture.hasAccessibilityPermission(),
                                                preferAX: settings.useAXFirst,
                                                frontmostAppName: previousApp?.localizedName,
                                                failureReason: outcome.failureReason,
                                                pasteboardReasonCode: outcome.pasteboardReasonCode,
                                                clipboardWaitAttempts: outcome.clipboardWaitAttempts)
        lastTextCaptureStatusSummary = diagnostic.diagnosticSummary
    }

    func currentTextCaptureStatusSummary() -> String? {
        lastTextCaptureStatusSummary
    }

    func undoWriteBackMenuTitle() -> String {
        WriteBackCommandFactory.undoMenuTitle(for: lastWriteBackRecord)
    }

    @objc func undoLastWriteBackFromMenu(_ sender: Any?) {
        undoLastWriteBack()
    }

    func undoLastWriteBack() {
        guard let record = lastWriteBackRecord else {
            lastWriteBackRecord = nil
            buildMenu()
            installMainMenu()
            return
        }
        guard record.isUndoAvailable else {
            lastWriteBackStatusSummary = record.diagnosticSummary
            lastWriteBackRecord = nil
            buildMenu()
            installMainMenu()
            return
        }
        lastWriteBackRecord = nil
        buildMenu()
        installMainMenu()
        guard let target = validatedUndoTarget(for: record) else {
            let reason = undoTargetUnavailableReason(for: record)
            let copiedOriginal = record.operation == .replace && !record.originalText.isEmpty
            if copiedOriginal {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.originalText, forType: .string)
            }
            let diagnostic = TextWriteBackUndoFallbackDiagnostic(record: record,
                                                                 reason: reason,
                                                                 copiedOriginalToPasteboard: copiedOriginal)
            lastWriteBackStatusSummary = diagnostic.diagnosticSummary
            presentWriteBackNotice(title: "无法自动撤销写回",
                                   message: diagnostic.noticeMessage)
            return
        }
        TextEditTransaction(targetApp: target)
            .replace(original: record.replacementText, with: record.originalText) { [weak self] in
                self?.lastWriteBackStatusSummary = "state=undo-completed, operation=\(record.operation.diagnosticName)"
            } failure: { [weak self] snapshot in
                self?.handleUnsafePasteboardUndo(record: record,
                                                 snapshot: snapshot)
            }
    }

    func handleUnsafePasteboardUndo(record: TextWriteBackRecord,
                                            snapshot: PasteboardSnapshot) {
        let diagnostic = TextWriteBackUndoFallbackDiagnostic(
            record: record,
            reason: "\(snapshot.undoRecoveryMessage) reason=\(snapshot.reasonCode), bytes=\(snapshot.totalByteCount), items=\(snapshot.itemCount), types=\(snapshot.typeCount)",
            copiedOriginalToPasteboard: false,
            recoveryOverride: snapshot.undoRecoveryMessage
        )
        lastWriteBackStatusSummary = diagnostic.diagnosticSummary
        presentWriteBackNotice(title: "已取消自动撤销写回",
                               message: diagnostic.noticeMessage,
                               showsDiagnosticsButton: true)
    }

    func validatedUndoTarget(for record: TextWriteBackRecord) -> NSRunningApplication? {
        guard record.isUndoAvailable,
              let target = record.targetApp,
              !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return target
    }

    func undoTargetUnavailableReason(for record: TextWriteBackRecord) -> String {
        switch record.undoState() {
        case .expired:
            return "上次写回记录已过期。"
        case .missingOriginal:
            return "缺少可恢复的原文。"
        case .missingReplacement:
            return "缺少上次写回内容。"
        case .targetTerminated:
            return "原应用已退出。"
        case .targetIsCurrentApp:
            return "目标应用是 SnapAI 自身。"
        case .available:
            return "原应用目标不可用。"
        }
    }
}
