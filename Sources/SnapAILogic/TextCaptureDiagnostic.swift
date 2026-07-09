import Foundation

public enum TextCaptureDiagnosticState: String, Equatable {
    case captured = "captured"
    case noSelection = "no-selection"
}

public enum TextCaptureDiagnosticMethod: String, Equatable {
    case accessibility = "accessibility"
    case clipboard = "clipboard"
    case service = "service"
}

public enum TextCaptureDiagnosticFailureReason: String, Equatable {
    case accessibilityEmptySelection = "accessibility-empty-selection"
    case pasteboardSnapshotUnsafe = "pasteboard-snapshot-unsafe"
    case clipboardUnchanged = "clipboard-unchanged"
    case clipboardEmpty = "clipboard-empty"
}

public struct TextCaptureDiagnostic: Equatable {
    public var state: TextCaptureDiagnosticState
    public var accessibilityGranted: Bool
    public var preferAX: Bool
    public var frontmostAppName: String?
    public var capturedCharacterCount: Int
    public var method: TextCaptureDiagnosticMethod?
    public var failureReason: TextCaptureDiagnosticFailureReason?
    public var pasteboardReasonCode: String?
    public var clipboardWaitAttempts: Int

    public static func captured(accessibilityGranted: Bool,
                                preferAX: Bool,
                                frontmostAppName: String?,
                                characterCount: Int,
                                method: TextCaptureDiagnosticMethod? = nil,
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

    public static func noSelection(accessibilityGranted: Bool,
                                   preferAX: Bool,
                                   frontmostAppName: String?,
                                   failureReason: TextCaptureDiagnosticFailureReason? = nil,
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

    public var diagnosticSummary: String {
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

    public var recoverySuggestion: String {
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
