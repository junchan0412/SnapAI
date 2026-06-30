import Foundation

struct ActionCommandDescriptor: Equatable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var keywords: String
    var shortcutText: String?
    var actionID: String
    var usageCount: Int = 0
}

enum ActionCommandFactory {
    static func descriptors(for actions: [AIAction],
                            usageCounts: [String: Int] = [:],
                            hotKeyDisplay: (AIAction) -> String?) -> [ActionCommandDescriptor] {
        var usedIDs = Set<String>()
        return actions
            .enumerated()
            .filter { $0.element.isEnabled }
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
                    shortcutText: hotKeyDisplay(action),
                    actionID: action.id,
                    usageCount: usageCount
                ))
            }
            .sorted {
                if $0.descriptor.usageCount != $1.descriptor.usageCount {
                    return $0.descriptor.usageCount > $1.descriptor.usageCount
                }
                return $0.index < $1.index
            }
            .map(\.descriptor)
    }

    private static func displayText(_ value: String,
                                    fallback: String,
                                    maxLength: Int) -> String {
        MarkdownExportSafety.metadata(value, fallback: fallback, maxLength: maxLength)
    }

    private static func safeUsageCount(for action: AIAction,
                                       usageCounts: [String: Int]) -> Int {
        let key = usageKey(for: action.name)
        return max(0, usageCounts[key] ?? 0)
    }

    private static func usageKey(for actionName: String) -> String {
        let trimmed = actionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "未命名动作" : trimmed
        guard resolved.count > AIAction.maxNameLength else { return resolved }
        return String(resolved.prefix(AIAction.maxNameLength))
    }
}
