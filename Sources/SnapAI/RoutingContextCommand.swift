import Foundation

enum RoutingContextCommandAction: Equatable {
    case setRoutingPreference(AIRoutingPreference)
    case clearContext
    case copyActiveContext
    case copyEffectiveSystemPrompt
    case copyContextStatus
    case setContextProfile(String)
}

struct RoutingContextCommandDescriptor: Equatable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var keywords: String
    var action: RoutingContextCommandAction
}

enum RoutingContextCommandFactory {
    static func routingDescriptors(current preference: AIRoutingPreference) -> [RoutingContextCommandDescriptor] {
        AIRoutingPreference.allCases.map { candidate in
            let isCurrent = candidate == preference
            return RoutingContextCommandDescriptor(
                id: "routing-\(candidate.id)",
                title: "路由偏好: \(candidate.rawValue)",
                subtitle: (isCurrent ? "当前 - " : "") + candidate.description,
                systemImage: isCurrent ? "checkmark.circle.fill" : "point.3.connected.trianglepath.dotted",
                keywords: MarkdownExportSafety.keywords([
                    "route routing preference model fallback speed quality cost ai 路由 偏好 模型 速度 质量 成本",
                    candidate.rawValue,
                    candidate.description
                ]),
                action: .setRoutingPreference(candidate)
            )
        }
    }

    static func contextDescriptors(profiles: [ContextProfile],
                                   activeProfileID: String) -> [RoutingContextCommandDescriptor] {
        var result: [RoutingContextCommandDescriptor] = []
        var usedIDs: Set<String> = ["context-clear", "context-copy-active"]
        if !activeProfileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(RoutingContextCommandDescriptor(
                id: "context-clear",
                title: "清空当前上下文",
                subtitle: "恢复为全局系统提示",
                systemImage: "xmark.circle",
                keywords: MarkdownExportSafety.keywords(["context profile clear project prompt 上下文 项目 清空"]),
                action: .clearContext
            ))
        }
        if let activeProfile = profiles.first(where: { $0.id == activeProfileID && isUsable($0) }) {
            let displayName = displayText(activeProfile.name, fallback: "未命名上下文")
            let searchableContent = displayText(activeProfile.content, fallback: "", maxLength: 240)
            result.append(RoutingContextCommandDescriptor(
                id: "context-copy-active",
                title: "复制当前上下文",
                subtitle: displayName,
                systemImage: "doc.on.clipboard",
                keywords: MarkdownExportSafety.keywords([
                    "context profile copy export markdown project prompt 上下文 项目 复制 导出",
                    displayName,
                    searchableContent
                ]),
                action: .copyActiveContext
            ))
        }
        result.append(RoutingContextCommandDescriptor(
            id: "context-copy-effective-prompt",
            title: "复制实际系统提示",
            subtitle: activeProfileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "全局 System Prompt"
                : "全局 System Prompt + 当前上下文",
            systemImage: "doc.text.magnifyingglass",
            keywords: MarkdownExportSafety.keywords(["system prompt effective context profile copy export markdown inspect 系统提示 上下文 实际 生效 复制 检查"]),
            action: .copyEffectiveSystemPrompt
        ))
        result.append(RoutingContextCommandDescriptor(
            id: "context-copy-status",
            title: "复制上下文状态",
            subtitle: "不包含上下文正文",
            systemImage: "list.bullet.clipboard",
            keywords: MarkdownExportSafety.keywords(["context profile status diagnostics copy metadata safe 上下文 状态 诊断 元信息 复制"]),
            action: .copyContextStatus
        ))

        for profile in profiles where isUsable(profile) {
            let isCurrent = profile.id == activeProfileID
            let displayName = displayText(profile.name, fallback: "未命名上下文")
            let searchableContent = displayText(profile.content, fallback: "", maxLength: 240)
            result.append(RoutingContextCommandDescriptor(
                id: descriptorID(profileID: profile.id, usedIDs: &usedIDs),
                title: "切换上下文: \(displayName)",
                subtitle: isCurrent ? "当前上下文包" : "项目背景、术语表和写作风格",
                systemImage: isCurrent ? "checkmark.circle.fill" : "text.book.closed",
                keywords: MarkdownExportSafety.keywords([
                    "context profile project prompt system 上下文 项目 背景 术语",
                    displayName,
                    searchableContent
                ]),
                action: .setContextProfile(profile.id)
            ))
        }
        return result
    }

    private static func isUsable(_ profile: ContextProfile) -> Bool {
        profile.isEnabled && !profile.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func descriptorID(profileID: String, usedIDs: inout Set<String>) -> String {
        CommandIdentifier.unique(prefix: "context",
                                 values: [profileID],
                                 usedIDs: &usedIDs)
    }

    private static func displayText(_ value: String,
                                    fallback: String,
                                    maxLength: Int = 80) -> String {
        MarkdownExportSafety.metadata(value, fallback: fallback, maxLength: maxLength)
    }
}
