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

    static func captured(accessibilityGranted: Bool,
                         preferAX: Bool,
                         frontmostAppName: String?,
                         characterCount: Int) -> TextCaptureDiagnostic {
        TextCaptureDiagnostic(state: .captured,
                              accessibilityGranted: accessibilityGranted,
                              preferAX: preferAX,
                              frontmostAppName: frontmostAppName,
                              capturedCharacterCount: characterCount)
    }

    static func noSelection(accessibilityGranted: Bool,
                            preferAX: Bool,
                            frontmostAppName: String?) -> TextCaptureDiagnostic {
        TextCaptureDiagnostic(state: .noSelection,
                              accessibilityGranted: accessibilityGranted,
                              preferAX: preferAX,
                              frontmostAppName: frontmostAppName,
                              capturedCharacterCount: 0)
    }

    var diagnosticSummary: String {
        let appName = MarkdownExportSafety.metadata(frontmostAppName,
                                                     fallback: "unknown",
                                                     maxLength: 80)
        return [
            "state=\(state.rawValue)",
            "accessibility=\(accessibilityGranted ? "granted" : "missing")",
            "preferAX=\(preferAX ? "yes" : "no")",
            "frontmostApp=\(appName)",
            "capturedChars=\(max(0, capturedCharacterCount))",
            "recovery=\(recoverySuggestion)"
        ].joined(separator: ", ")
    }

    var recoverySuggestion: String {
        switch state {
        case .captured:
            return "无需处理"
        case .noSelection:
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
