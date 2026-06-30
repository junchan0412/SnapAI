import AppKit

enum TextWriteBackOperation: Equatable {
    case replace
    case append

    var diagnosticName: String {
        switch self {
        case .replace: return "replace"
        case .append: return "append"
        }
    }
}

enum TextWriteBackTargetState: Equatable {
    case missing
    case running
    case terminated
    case currentApp

    var diagnosticName: String {
        switch self {
        case .missing: return "missing"
        case .running: return "running"
        case .terminated: return "terminated"
        case .currentApp: return "current-app"
        }
    }
}

enum TextWriteBackUndoState: Equatable {
    case available
    case expired
    case missingOriginal
    case missingReplacement
    case targetTerminated
    case targetIsCurrentApp

    var diagnosticName: String {
        switch self {
        case .available: return "available"
        case .expired: return "expired"
        case .missingOriginal: return "missing-original"
        case .missingReplacement: return "missing-replacement"
        case .targetTerminated: return "target-terminated"
        case .targetIsCurrentApp: return "target-current-app"
        }
    }
}

struct TextWriteBackRecord {
    static let expirationInterval: TimeInterval = 10 * 60

    let targetApp: NSRunningApplication?
    let operation: TextWriteBackOperation
    let originalText: String
    let replacementText: String
    let createdAt: Date

    init(targetApp: NSRunningApplication?,
         operation: TextWriteBackOperation = .replace,
         originalText: String,
         replacementText: String,
         createdAt: Date = Date()) {
        self.targetApp = targetApp
        self.operation = operation
        self.originalText = originalText
        self.replacementText = replacementText
        self.createdAt = createdAt
    }

    var isUndoAvailable: Bool {
        undoState() == .available
    }

    var targetState: TextWriteBackTargetState {
        Self.resolvedTargetState(processIdentifier: targetApp?.processIdentifier,
                                 isTerminated: targetApp?.isTerminated ?? false)
    }

    static func resolvedTargetState(processIdentifier: pid_t?,
                                    isTerminated: Bool,
                                    currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier) -> TextWriteBackTargetState {
        guard let processIdentifier else { return .missing }
        if isTerminated { return .terminated }
        if processIdentifier == currentProcessIdentifier { return .currentApp }
        return .running
    }

    func undoState(at date: Date = Date()) -> TextWriteBackUndoState {
        guard !replacementText.isEmpty,
              date.timeIntervalSince(createdAt) <= Self.expirationInterval else {
            return replacementText.isEmpty ? .missingReplacement : .expired
        }
        switch targetState {
        case .terminated:
            return .targetTerminated
        case .currentApp:
            return .targetIsCurrentApp
        case .missing, .running:
            break
        }
        switch operation {
        case .replace:
            return originalText.isEmpty ? .missingOriginal : .available
        case .append:
            return .available
        }
    }

    var undoTitle: String {
        let appName = targetApp?.localizedName ?? "原应用"
        switch operation {
        case .replace:
            return "撤销上次替换到 \(appName)"
        case .append:
            return "撤销上次追加到 \(appName)"
        }
    }

    var diagnosticSummary: String {
        let undo = undoState()
        let state = undo == .available ? "available" : "unavailable"
        let appName = MarkdownExportSafety.metadata(targetApp?.localizedName,
                                                     fallback: "unknown",
                                                     maxLength: 80)
        let age = max(0, Int(Date().timeIntervalSince(createdAt)))
        return "state=\(state), undo=\(undo.diagnosticName), operation=\(operation.diagnosticName), target=\(appName), targetState=\(targetState.diagnosticName), ageSeconds=\(age), originalChars=\(originalText.count), replacementChars=\(replacementText.count), recovery=\(recoverySuggestion)"
    }

    var recoverySuggestion: String {
        switch undoState() {
        case .available:
            return "可通过命令面板或菜单撤销上次写回"
        case .expired:
            return "撤销窗口已过期; 请在目标应用中手动恢复"
        case .missingOriginal:
            return "缺少原文快照; 请在目标应用中手动恢复"
        case .missingReplacement:
            return "缺少写回内容; 请重新复制结果或手动恢复"
        case .targetTerminated:
            return "目标应用已退出; 请重新打开后手动恢复"
        case .targetIsCurrentApp:
            return "目标是 SnapAI; 请切回原应用后手动恢复"
        }
    }
}

struct TextWriteBackUndoFallbackDiagnostic: Equatable {
    var operation: TextWriteBackOperation
    var undoState: TextWriteBackUndoState
    var targetState: TextWriteBackTargetState
    var targetName: String?
    var reason: String
    var copiedOriginalToPasteboard: Bool
    var originalCharacterCount: Int
    var replacementCharacterCount: Int
    var recoveryOverride: String?

    init(record: TextWriteBackRecord,
         reason: String,
         copiedOriginalToPasteboard: Bool,
         recoveryOverride: String? = nil) {
        self.operation = record.operation
        self.undoState = record.undoState()
        self.targetState = record.targetState
        self.targetName = record.targetApp?.localizedName
        self.reason = reason
        self.copiedOriginalToPasteboard = copiedOriginalToPasteboard
        self.originalCharacterCount = max(0, record.originalText.count)
        self.replacementCharacterCount = max(0, record.replacementText.count)
        self.recoveryOverride = recoveryOverride
    }

    var diagnosticSummary: String {
        let appName = MarkdownExportSafety.metadata(targetName,
                                                     fallback: "unknown",
                                                     maxLength: 80)
        let safeReason = SensitiveTextSanitizer.sanitizedMessage(reason,
                                                                 limit: 180)
        return [
            "state=undo-fallback",
            "undo=\(undoState.diagnosticName)",
            "operation=\(operation.diagnosticName)",
            "target=\(appName)",
            "targetState=\(targetState.diagnosticName)",
            "copiedOriginalToPasteboard=\(copiedOriginalToPasteboard ? "yes" : "no")",
            "originalChars=\(originalCharacterCount)",
            "replacementChars=\(replacementCharacterCount)",
            "recovery=\(recoverySuggestion)",
            "reason=\(safeReason.isEmpty ? "unknown" : safeReason)"
        ].joined(separator: ", ")
    }

    var noticeMessage: String {
        let safeReason = SensitiveTextSanitizer.sanitizedMessage(reason,
                                                                 limit: 220)
        let normalizedReason = safeReason.isEmpty ? "无法自动撤销上次写回。" : safeReason
        return [
            normalizedReason,
            "建议: \(recoverySuggestion)"
        ].joined(separator: "\n\n")
    }

    var recoverySuggestion: String {
        if let recoveryOverride {
            let safeOverride = SensitiveTextSanitizer.sanitizedMessage(recoveryOverride,
                                                                       limit: 220)
            if !safeOverride.isEmpty {
                return safeOverride
            }
        }
        if copiedOriginalToPasteboard {
            return "替换前的原文已复制到剪贴板; 请回到目标应用手动粘贴恢复"
        }
        switch operation {
        case .replace:
            return "请在目标应用中使用系统撤销,或从历史记录中找回替换前内容"
        case .append:
            return "请在目标应用中使用系统撤销,或手动移除上次追加内容"
        }
    }
}

struct TextWriteBackFallbackDiagnostic: Equatable {
    var operation: TextWriteBackOperation
    var targetState: TextWriteBackTargetState
    var targetName: String?
    var reason: String
    var copiedToPasteboard: Bool
    var originalCharacterCount: Int
    var payloadCharacterCount: Int
    var recoveryOverride: String?

    init(operation: TextWriteBackOperation,
         targetApp: NSRunningApplication?,
         reason: String,
         copiedToPasteboard: Bool,
         originalCharacterCount: Int,
         payloadCharacterCount: Int,
         recoveryOverride: String? = nil) {
        self.operation = operation
        self.targetState = Self.targetState(for: targetApp)
        self.targetName = targetApp?.localizedName
        self.reason = reason
        self.copiedToPasteboard = copiedToPasteboard
        self.originalCharacterCount = max(0, originalCharacterCount)
        self.payloadCharacterCount = max(0, payloadCharacterCount)
        self.recoveryOverride = recoveryOverride
    }

    var diagnosticSummary: String {
        let appName = MarkdownExportSafety.metadata(targetName,
                                                     fallback: "unknown",
                                                     maxLength: 80)
        let safeReason = SensitiveTextSanitizer.sanitizedMessage(reason,
                                                                 limit: 180)
        return [
            "state=fallback-copied",
            "operation=\(operation.diagnosticName)",
            "target=\(appName)",
            "targetState=\(targetState.diagnosticName)",
            "copiedToPasteboard=\(copiedToPasteboard ? "yes" : "no")",
            "originalChars=\(originalCharacterCount)",
            "payloadChars=\(payloadCharacterCount)",
            "recovery=\(recoverySuggestion)",
            "reason=\(safeReason.isEmpty ? "unknown" : safeReason)"
        ].joined(separator: ", ")
    }

    var noticeMessage: String {
        let safeReason = SensitiveTextSanitizer.sanitizedMessage(reason,
                                                                 limit: 220)
        let normalizedReason = safeReason.isEmpty ? "无法自动写回到目标应用。" : safeReason
        let pasteboardStatus = copiedToPasteboard ? "结果已复制到剪贴板。" : "结果未能自动复制到剪贴板。"
        return [
            normalizedReason,
            pasteboardStatus,
            "建议: \(recoverySuggestion)"
        ].joined(separator: "\n\n")
    }

    var recoverySuggestion: String {
        if let recoveryOverride {
            let safeOverride = SensitiveTextSanitizer.sanitizedMessage(recoveryOverride,
                                                                       limit: 220)
            if !safeOverride.isEmpty {
                return safeOverride
            }
        }
        var parts: [String] = []
        switch targetState {
        case .missing:
            parts.append("回到原应用后手动粘贴剪贴板内容")
        case .terminated:
            parts.append("重新打开目标应用后手动粘贴剪贴板内容")
        case .currentApp:
            parts.append("切回需要写入的应用后手动粘贴剪贴板内容")
        case .running:
            parts.append("确认目标输入框仍聚焦后手动粘贴剪贴板内容")
        }
        switch operation {
        case .replace:
            parts.append("如需替换请重新选中原文")
        case .append:
            parts.append("如需追加请定位到目标位置")
        }
        if !copiedToPasteboard {
            parts.append("若剪贴板未更新请手动复制结果")
        }
        return parts.joined(separator: "; ")
    }

    private static func targetState(for app: NSRunningApplication?) -> TextWriteBackTargetState {
        TextWriteBackRecord.resolvedTargetState(processIdentifier: app?.processIdentifier,
                                                isTerminated: app?.isTerminated ?? false)
    }
}

@MainActor
struct TextEditTransaction {
    var targetApp: NSRunningApplication?
    var selectionSnapshot: TextSelectionSnapshot?
    var focusDelay: TimeInterval = 0.18
    var restoreDelay: TimeInterval = 0.35

    func replace(original: String,
                 with text: String,
                 completion: (() -> Void)? = nil,
                 failure: ((PasteboardSnapshot) -> Void)? = nil) {
        paste(text) {
            guard TextCapture.selectedTextViaAX()?.isEmpty != false else { return 0.03 }
            if selectionSnapshot?.restoreSelection() == true {
                return 0.08
            }
            TextCapture.sendShiftLeftArrow(repeat: original.count)
            return Self.selectionDelay(forCharacterCount: original.count)
        } completion: {
            completion?()
        } failure: { snapshot in
            failure?(snapshot)
        }
    }

    func append(_ text: String,
                completion: (() -> Void)? = nil,
                failure: ((PasteboardSnapshot) -> Void)? = nil) {
        paste("\n" + text) {
            TextCapture.sendRightArrow()
            return 0.05
        } completion: {
            completion?()
        } failure: { snapshot in
            failure?(snapshot)
        }
    }

    nonisolated static func selectionDelay(forCharacterCount count: Int) -> TimeInterval {
        guard count > 0 else { return 0.03 }
        return min(0.75, 0.05 + Double(count) * 0.0015)
    }

    private func paste(_ text: String,
                       beforePaste: (() -> TimeInterval)? = nil,
                       completion: (() -> Void)? = nil,
                       failure: ((PasteboardSnapshot) -> Void)? = nil) {
        let pasteboard = NSPasteboard.general
        let previousSnapshot = TextCapture.snapshotPasteboard(pasteboard)
        guard previousSnapshot.canRestore else {
            failure?(previousSnapshot)
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let injectedChangeCount = pasteboard.changeCount

        targetApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay) {
            let pasteDelay = beforePaste?() ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
                TextCapture.sendCmdV()
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                    TextCapture.restorePasteboardIfUnchanged(pasteboard,
                                                             snapshot: previousSnapshot,
                                                             expectedChangeCount: injectedChangeCount)
                    TextCapture.clearRecentSelectionSnapshot()
                    completion?()
                }
            }
        }
    }
}
