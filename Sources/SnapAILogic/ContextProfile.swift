import Foundation

package struct ContextProfile: Codable, Identifiable, Equatable {
    package var id: String
    package var name: String
    package var content: String
    package var isEnabled: Bool

    package static func defaults() -> [ContextProfile] {
        [
            ContextProfile(name: "通用上下文", content: "", isEnabled: false)
        ]
    }

    package func markdownExport(isActive: Bool) -> String {
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

    package init(id: String = UUID().uuidString,
                 name: String,
                 content: String,
                 isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.content = content
        self.isEnabled = isEnabled
    }
}

package struct ContextProfileUpsertResult: Equatable {
    package var profile: ContextProfile
    package var didUpdate: Bool
}
