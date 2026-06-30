import Foundation

struct HistoryContextCommandDescriptor: Equatable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var keywords: String
    var criteria: HistoryFilterCriteria
}

enum HistoryContextCommandFactory {
    static func descriptors(for history: [HistoryEntry], facetLimit: Int = 6) -> [HistoryContextCommandDescriptor] {
        let usableHistory = history.filter { HistoryContextProfileBuilder.isUsableForContext($0) }
        guard !usableHistory.isEmpty else { return [] }

        var usedIDs: Set<String> = ["history-context-all", "history-context-favorites"]
        var result: [HistoryContextCommandDescriptor] = [
            HistoryContextCommandDescriptor(
                id: "history-context-all",
                title: "从历史创建上下文包",
                subtitle: "\(usableHistory.count) 条可用记录",
                systemImage: "text.badge.plus",
                keywords: MarkdownExportSafety.keywords(["history context profile create memory project prompt 历史 上下文 项目 记忆 创建"]),
                criteria: HistoryFilterCriteria()
            )
        ]

        for action in HistoryFilterCriteria.rankedFacetCounts(usableHistory.map(\.displayActionName)).prefix(facetLimit) {
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
                criteria: HistoryFilterCriteria(actionFilter: action.value)
            ))
        }

        for model in HistoryFilterCriteria.rankedFacetCounts(usableHistory.map(\.displayModelFilterName)).prefix(facetLimit) {
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
                criteria: HistoryFilterCriteria(modelFilter: model.value)
            ))
        }

        for tag in HistoryFilterCriteria.rankedFacetCounts(usableHistory.flatMap(\.displayTags)).prefix(facetLimit) {
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
                criteria: HistoryFilterCriteria(tagFilter: tag.value)
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
                criteria: HistoryFilterCriteria(favoriteOnly: true)
            ))
        }

        return result
    }

    private static func displayText(_ value: String,
                                    fallback: String,
                                    maxLength: Int) -> String {
        MarkdownExportSafety.metadata(value, fallback: fallback, maxLength: maxLength)
    }
}
