import Foundation

struct ContextProfile: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var content: String
    var isEnabled: Bool = true

    static func defaults() -> [ContextProfile] {
        [
            ContextProfile(name: "通用上下文", content: "", isEnabled: false)
        ]
    }

    func markdownExport(isActive: Bool) -> String {
        let displayName = MarkdownExportSafety.metadata(name,
                                                         fallback: "未命名上下文",
                                                         maxLength: 80)
        let displayContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        # \(displayName)

        - 状态: \(isActive ? "使用中" : "未使用")
        - 启用: \(isEnabled ? "是" : "否")
        - 字符数: \(displayContent.count)

        ## 内容

        \(displayContent.isEmpty ? "无内容" : displayContent)
        """
    }
}

struct ContextProfileUpsertResult: Equatable {
    var profile: ContextProfile
    var didUpdate: Bool
}
