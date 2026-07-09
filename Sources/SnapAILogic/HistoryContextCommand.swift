import Foundation

public struct HistoryContextCommandInput: Equatable {
    public var displayActionName: String
    public var displayModelFilterName: String
    public var displayTags: [String]
    public var isFavorite: Bool
    public var isUsableForContext: Bool

    public init(displayActionName: String,
                displayModelFilterName: String,
                displayTags: [String],
                isFavorite: Bool,
                isUsableForContext: Bool) {
        self.displayActionName = displayActionName
        self.displayModelFilterName = displayModelFilterName
        self.displayTags = displayTags
        self.isFavorite = isFavorite
        self.isUsableForContext = isUsableForContext
    }
}

public struct HistoryContextCommandCriteria: Equatable {
    public var actionFilter: String?
    public var modelFilter: String?
    public var tagFilter: String?
    public var favoriteOnly: Bool

    public init(actionFilter: String? = nil,
                modelFilter: String? = nil,
                tagFilter: String? = nil,
                favoriteOnly: Bool = false) {
        self.actionFilter = actionFilter
        self.modelFilter = modelFilter
        self.tagFilter = tagFilter
        self.favoriteOnly = favoriteOnly
    }
}

public struct HistoryContextCommandDescriptor: Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: String
    public var criteria: HistoryContextCommandCriteria
}

public enum HistoryContextCommandFactory {
    public static func descriptors(for history: [HistoryContextCommandInput],
                                   facetLimit: Int = 6) -> [HistoryContextCommandDescriptor] {
        let usableHistory = history.filter(\.isUsableForContext)
        guard !usableHistory.isEmpty else { return [] }

        var usedIDs: Set<String> = ["history-context-all", "history-context-favorites"]
        var result: [HistoryContextCommandDescriptor] = [
            HistoryContextCommandDescriptor(
                id: "history-context-all",
                title: "从历史创建上下文包",
                subtitle: "\(usableHistory.count) 条可用记录",
                systemImage: "text.badge.plus",
                keywords: MarkdownExportSafety.keywords(["history context profile create memory project prompt 历史 上下文 项目 记忆 创建"]),
                criteria: HistoryContextCommandCriteria()
            )
        ]

        for action in rankedFacetCounts(usableHistory.map(\.displayActionName), fallback: "未命名动作").prefix(facetLimit) {
            let actionTitle = displayText(action.value, fallback: "未命名动作", maxLength: 80)
            result.append(HistoryContextCommandDescriptor(
                id: CommandIdentifier.unique(prefix: "history-context-action",
                                             values: [action.value],
                                             usedIDs: &usedIDs),
                title: "从\(actionTitle)历史创建上下文",
                subtitle: "\(action.count) 条可用记录",
                systemImage: "wand.and.stars",
                keywords: MarkdownExportSafety.keywords([
                    "history context profile create action memory 历史 上下文 动作 记忆",
                    actionTitle
                ]),
                criteria: HistoryContextCommandCriteria(actionFilter: action.value)
            ))
        }

        for model in rankedFacetCounts(usableHistory.map(\.displayModelFilterName), fallback: "未知模型").prefix(facetLimit) {
            let modelTitle = displayText(model.value, fallback: "未知模型", maxLength: 120)
            result.append(HistoryContextCommandDescriptor(
                id: CommandIdentifier.unique(prefix: "history-context-model",
                                             values: [model.value],
                                             usedIDs: &usedIDs),
                title: "从模型「\(modelTitle)」历史创建上下文",
                subtitle: "\(model.count) 条可用记录",
                systemImage: "cpu",
                keywords: MarkdownExportSafety.keywords([
                    "history context profile create model memory 模型 历史 上下文 记忆",
                    modelTitle
                ]),
                criteria: HistoryContextCommandCriteria(modelFilter: model.value)
            ))
        }

        for tag in rankedFacetCounts(usableHistory.flatMap { dedupedFacetValues($0.displayTags, fallback: nil) },
                                     fallback: nil).prefix(facetLimit) {
            let tagTitle = displayText(tag.value, fallback: "未命名标签", maxLength: 80)
            result.append(HistoryContextCommandDescriptor(
                id: CommandIdentifier.unique(prefix: "history-context-tag",
                                             values: [tag.value],
                                             usedIDs: &usedIDs),
                title: "从标签「\(tagTitle)」历史创建上下文",
                subtitle: "\(tag.count) 条可用记录",
                systemImage: "tag.fill",
                keywords: MarkdownExportSafety.keywords([
                    "history context profile create tag memory 标签 历史 上下文 记忆",
                    tagTitle
                ]),
                criteria: HistoryContextCommandCriteria(tagFilter: tag.value)
            ))
        }

        let favoriteCount = usableHistory.filter(\.isFavorite).count
        if favoriteCount > 0 {
            result.append(HistoryContextCommandDescriptor(
                id: "history-context-favorites",
                title: "从收藏历史创建上下文",
                subtitle: "\(favoriteCount) 条可用收藏记录",
                systemImage: "star.fill",
                keywords: MarkdownExportSafety.keywords(["history context profile create favorite starred memory 收藏 历史 上下文 记忆"]),
                criteria: HistoryContextCommandCriteria(favoriteOnly: true)
            ))
        }

        return result
    }

    private static func rankedFacetCounts(_ values: [String],
                                          fallback: String?) -> [(value: String, count: Int)] {
        values
            .compactMap { normalizedFacetValue($0, fallback: fallback) }
            .reduce(into: [String: Int]()) { counts, value in
                counts[value, default: 0] += 1
            }
            .map { (value: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return facetValuePrecedes($0.value, $1.value)
            }
    }

    private static func dedupedFacetValues(_ values: [String],
                                           fallback: String?) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values.compactMap({ normalizedFacetValue($0, fallback: fallback) }) {
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static func normalizedFacetValue(_ value: String,
                                             fallback: String?) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        return trimmed
    }

    private static func facetValuePrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs,
                    options: [.numeric],
                    range: nil,
                    locale: Locale(identifier: "zh_Hans_CN")) == .orderedAscending
    }

    private static func displayText(_ value: String,
                                    fallback: String,
                                    maxLength: Int) -> String {
        MarkdownExportSafety.metadata(value, fallback: fallback, maxLength: maxLength)
    }
}
