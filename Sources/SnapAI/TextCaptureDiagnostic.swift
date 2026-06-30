import Foundation

enum TextCaptureDiagnosticState: String, Equatable {
    case captured = "captured"
    case noSelection = "no-selection"
}

struct TextCaptureDiagnostic: Equatable {
    var state: TextCaptureDiagnosticState
    var accessibilityGranted: Bool
    var preferAX: Bool
    var frontmostAppName: String?
    var capturedCharacterCount: Int
    var method: TextCaptureMethod?
    var failureReason: TextCaptureFailureReason?
    var pasteboardReasonCode: String?
    var clipboardWaitAttempts: Int

    static func captured(accessibilityGranted: Bool,
                         preferAX: Bool,
                         frontmostAppName: String?,
                         characterCount: Int,
                         method: TextCaptureMethod? = nil,
                         clipboardWaitAttempts: Int = 0) -> TextCaptureDiagnostic {
        TextCaptureDiagnostic(state: .captured,
                              accessibilityGranted: accessibilityGranted,
                              preferAX: preferAX,
                              frontmostAppName: frontmostAppName,
                              capturedCharacterCount: characterCount,
                              method: method,
                              failureReason: nil,
                              pasteboardReasonCode: nil,
                              clipboardWaitAttempts: max(0, clipboardWaitAttempts))
    }

    static func noSelection(accessibilityGranted: Bool,
                            preferAX: Bool,
                            frontmostAppName: String?,
                            failureReason: TextCaptureFailureReason? = nil,
                            pasteboardReasonCode: String? = nil,
                            clipboardWaitAttempts: Int = 0) -> TextCaptureDiagnostic {
        TextCaptureDiagnostic(state: .noSelection,
                              accessibilityGranted: accessibilityGranted,
                              preferAX: preferAX,
                              frontmostAppName: frontmostAppName,
                              capturedCharacterCount: 0,
                              method: nil,
                              failureReason: failureReason,
                              pasteboardReasonCode: pasteboardReasonCode,
                              clipboardWaitAttempts: max(0, clipboardWaitAttempts))
    }

    var diagnosticSummary: String {
        let appName = MarkdownExportSafety.metadata(frontmostAppName,
                                                     fallback: "unknown",
                                                     maxLength: 80)
        var parts = [
            "state=\(state.rawValue)",
            "accessibility=\(accessibilityGranted ? "granted" : "missing")",
            "preferAX=\(preferAX ? "yes" : "no")",
            "frontmostApp=\(appName)",
            "capturedChars=\(max(0, capturedCharacterCount))"
        ]
        if let method {
            parts.append("method=\(method.rawValue)")
        }
        if let failureReason {
            parts.append("failure=\(failureReason.rawValue)")
        }
        if let pasteboardReasonCode {
            parts.append("pasteboard=\(pasteboardReasonCode)")
        }
        if clipboardWaitAttempts > 0 {
            parts.append("clipboardWaitAttempts=\(clipboardWaitAttempts)")
        }
        parts.append("recovery=\(recoverySuggestion)")
        return parts.joined(separator: ", ")
    }

    var recoverySuggestion: String {
        switch state {
        case .captured:
            return "无需处理"
        case .noSelection:
            if failureReason == .pasteboardSnapshotUnsafe {
                return "当前剪贴板内容过大或格式过多,为保护剪贴板已跳过复制兜底; 可打开快捷提问"
            }
            if failureReason == .clipboardUnchanged {
                return "复制兜底未检测到剪贴板更新; 请确认目标应用允许复制,或打开快捷提问"
            }
            if !accessibilityGranted {
                return "授予辅助功能权限后重试; 也可打开快捷提问"
            }
            if preferAX {
                return "重新选中文字后重试; 若目标应用不兼容,可打开快捷提问"
            }
            return "重新选中文字后重试; 确认目标应用允许复制,也可打开快捷提问"
        }
    }
}
