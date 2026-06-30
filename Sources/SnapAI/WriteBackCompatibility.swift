import Foundation

struct WriteBackCompatibilityProfile: Equatable {
    var appNames: [String]
    var displayName: String
    var recoveryHint: String
}

enum WriteBackCompatibility {
    static let profiles: [WriteBackCompatibilityProfile] = [
        WriteBackCompatibilityProfile(
            appNames: ["Safari", "Google Chrome", "Chrome", "Microsoft Edge", "Edge"],
            displayName: "浏览器",
            recoveryHint: "浏览器写回失败时,请确认网页输入框仍聚焦; 若页面拦截粘贴,可先复制结果再用页面原生编辑器粘贴"
        ),
        WriteBackCompatibilityProfile(
            appNames: ["微信", "WeChat"],
            displayName: "微信",
            recoveryHint: "微信输入框可能在窗口切换后丢失焦点; 请点回输入框后手动粘贴,必要时重新选中文本再替换"
        ),
        WriteBackCompatibilityProfile(
            appNames: ["飞书", "Lark", "Feishu"],
            displayName: "飞书",
            recoveryHint: "飞书富文本编辑器可能延迟接收粘贴; 请点回编辑区并等待光标稳定后重试"
        ),
        WriteBackCompatibilityProfile(
            appNames: ["Obsidian"],
            displayName: "Obsidian",
            recoveryHint: "Obsidian 建议在编辑模式下写回; 阅读模式或预览区域请先切回编辑区"
        ),
        WriteBackCompatibilityProfile(
            appNames: ["Notion"],
            displayName: "Notion",
            recoveryHint: "Notion 块编辑器可能改变当前块焦点; 请先定位到目标块,失败时使用剪贴板手动粘贴"
        ),
        WriteBackCompatibilityProfile(
            appNames: ["Xcode"],
            displayName: "Xcode",
            recoveryHint: "Xcode 写回前请确认编辑器拥有焦点且没有弹出补全窗口; 失败时可用系统撤销或手动粘贴"
        ),
        WriteBackCompatibilityProfile(
            appNames: ["Microsoft Word", "Word"],
            displayName: "Word",
            recoveryHint: "Word 富文本区域可能改写纯文本粘贴行为; 请确认文档编辑区聚焦,必要时使用选择性粘贴"
        )
    ]

    static func profile(for appName: String?) -> WriteBackCompatibilityProfile? {
        let normalized = normalizedAppName(appName)
        guard !normalized.isEmpty else { return nil }
        return profiles.first { profile in
            profile.appNames.contains { normalizedAppName($0) == normalized }
        }
    }

    static func recoveryHint(for appName: String?) -> String? {
        profile(for: appName)?.recoveryHint
    }

    static func diagnosticSummary(for appName: String?) -> String {
        guard let profile = profile(for: appName) else { return "unknown" }
        return profile.displayName
    }

    private static func normalizedAppName(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[\s._-]+"#,
                                  with: "",
                                  options: .regularExpression)
    }
}
