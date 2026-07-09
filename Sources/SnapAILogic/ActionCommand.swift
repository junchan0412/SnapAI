import Foundation

public struct ActionCommandInput: Equatable {
    public static let maxNameLength = 80

    public var id: String
    public var name: String
    public var group: String
    public var icon: String
    public var isEnabled: Bool
    public var shortcutText: String?

    public init(id: String,
                name: String,
                group: String,
                icon: String,
                isEnabled: Bool,
                shortcutText: String?) {
        self.id = id
        self.name = name
        self.group = group
        self.icon = icon
        self.isEnabled = isEnabled
        self.shortcutText = shortcutText
    }
}

public struct ActionCommandDescriptor: Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: String
    public var shortcutText: String?
    public var actionID: String
    public var usageCount: Int = 0
}

public enum ActionCommandFactory {
    public static func descriptors(for actions: [ActionCommandInput],
                                   usageCounts: [String: Int] = [:]) -> [ActionCommandDescriptor] {
        var usedIDs = Set<String>()
        return actions
            .enumerated()
            .filter(\.element.isEnabled)
            .map { index, action in
                let title = displayText(action.name, fallback: "未命名动作", maxLength: 80)
                let group = displayText(action.group, fallback: "", maxLength: 80)
                let usageCount = safeUsageCount(for: action, usageCounts: usageCounts)
                let baseSubtitle = group.isEmpty
                    ? "动作"
                    : "动作 - \(group)"
                let subtitle = usageCount > 0
                    ? "\(baseSubtitle) · 常用 \(usageCount) 次"
                    : baseSubtitle
                let keywords = usageCount > 0
                    ? MarkdownExportSafety.keywords(["action prompt recent frequent 常用 最近 使用 \(usageCount)", title, group])
                    : MarkdownExportSafety.keywords(["action prompt", title, group])
                return (index: index,
                        descriptor: ActionCommandDescriptor(
                    id: CommandIdentifier.unique(prefix: "action",
                                                 values: [action.id],
                                                 usedIDs: &usedIDs),
                    title: title,
                    subtitle: subtitle,
                    systemImage: action.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "wand.and.stars"
                        : action.icon,
                    keywords: keywords,
                    shortcutText: action.shortcutText,
                    actionID: action.id,
                    usageCount: usageCount
                ))
            }
            .sorted { (lhs: (index: Int, descriptor: ActionCommandDescriptor),
                       rhs: (index: Int, descriptor: ActionCommandDescriptor)) in
                if lhs.descriptor.usageCount != rhs.descriptor.usageCount {
                    return lhs.descriptor.usageCount > rhs.descriptor.usageCount
                }
                return lhs.index < rhs.index
            }
            .map(\.descriptor)
    }

    private static func displayText(_ value: String,
                                    fallback: String,
                                    maxLength: Int) -> String {
        MarkdownExportSafety.metadata(value, fallback: fallback, maxLength: maxLength)
    }

    private static func safeUsageCount(for action: ActionCommandInput,
                                       usageCounts: [String: Int]) -> Int {
        let key = usageKey(for: action.name)
        return max(0, usageCounts[key] ?? 0)
    }

    private static func usageKey(for actionName: String) -> String {
        let trimmed = actionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "未命名动作" : trimmed
        guard resolved.count > ActionCommandInput.maxNameLength else { return resolved }
        return String(resolved.prefix(ActionCommandInput.maxNameLength))
    }
}
