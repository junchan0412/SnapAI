import Foundation

struct HistoryExportCommandDescriptor: Equatable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var keywords: String
    var criteria: HistoryFilterCriteria
}

enum HistoryExportCommandFactory {
    static func descriptors(for history: [HistoryEntry], facetLimit: Int = 8) -> [HistoryExportCommandDescriptor] {
        guard !history.isEmpty else { return [] }
        var usedIDs: Set<String> = ["history-copy-markdown", "history-copy-favorites-markdown"]
        var result: [HistoryExportCommandDescriptor] = [
            HistoryExportCommandDescriptor(
                id: "history-copy-markdown",
                title: "复制全部历史",
                subtitle: "\(history.count) 条记录,Markdown",
                systemImage: "doc.on.clipboard",
                keywords: MarkdownExportSafety.keywords(["history export copy markdown all 历史 导出 复制 全部"]),
                criteria: HistoryFilterCriteria()
            )
        ]

        for action in HistoryFilterCriteria.rankedFacetCounts(history.map(\.displayActionName)).prefix(facetLimit) {
            let actionTitle = displayText(action.value, fallback: "未命名动作", maxLength: 80)
            result.append(HistoryExportCommandDescriptor(
                id: CommandIdentifier.unique(prefix: "history-copy-action",
                                             values: [action.value],
                                             usedIDs: &usedIDs),
                title: "复制\(actionTitle)历史",
                subtitle: "\(action.count) 条记录,Markdown",
                systemImage: "tray.and.arrow.up",
                keywords: MarkdownExportSafety.keywords([
                    "history export copy markdown action 历史 导出 复制 动作",
                    actionTitle
                ]),
                criteria: HistoryFilterCriteria(actionFilter: action.value)
            ))
        }

        for model in HistoryFilterCriteria.rankedFacetCounts(history.map(\.displayModelFilterName)).prefix(facetLimit) {
            let modelTitle = displayText(model.value, fallback: "未知模型", maxLength: 120)
            result.append(HistoryExportCommandDescriptor(
                id: CommandIdentifier.unique(prefix: "history-copy-model",
                                             values: [model.value],
                                             usedIDs: &usedIDs),
                title: "复制模型「\(modelTitle)」历史",
                subtitle: "\(model.count) 条记录,Markdown",
                systemImage: "cpu",
                keywords: MarkdownExportSafety.keywords([
                    "history export copy markdown model 模型 历史 导出 复制",
                    modelTitle
                ]),
                criteria: HistoryFilterCriteria(modelFilter: model.value)
            ))
        }

        for tag in prioritizedTagCounts(from: history, facetLimit: facetLimit) {
            let tagTitle = displayText(tag.value, fallback: "未命名标签", maxLength: 80)
            result.append(HistoryExportCommandDescriptor(
                id: CommandIdentifier.unique(prefix: "history-copy-tag",
                                             values: [tag.value],
                                             usedIDs: &usedIDs),
                title: "复制标签「\(tagTitle)」历史",
                subtitle: "\(tag.count) 条记录,Markdown",
                systemImage: "tag.fill",
                keywords: MarkdownExportSafety.keywords([
                    "history export copy markdown tag 标签 历史 导出 复制",
                    tagTitle
                ]),
                criteria: HistoryFilterCriteria(tagFilter: tag.value)
            ))
        }

        let favoriteCount = history.filter(\.isFavorite).count
        if favoriteCount > 0 {
            result.append(HistoryExportCommandDescriptor(
                id: "history-copy-favorites-markdown",
                title: "复制收藏历史",
                subtitle: "\(favoriteCount) 条收藏记录,Markdown",
                systemImage: "star.fill",
                keywords: MarkdownExportSafety.keywords(["history export copy markdown favorite starred 收藏 历史 导出 复制"]),
                criteria: HistoryFilterCriteria(favoriteOnly: true)
            ))
        }

        return result
    }

    private static func prioritizedTagCounts(from history: [HistoryEntry],
                                             facetLimit: Int) -> [(value: String, count: Int)] {
        let counts = HistoryFilterCriteria.rankedFacetCounts(history.flatMap(\.displayTags))
        var result = Array(counts.prefix(facetLimit))
        var included = Set(result.map(\.value))
        for tag in PrivacyHistoryTag.prioritizedForHistoryExport where !included.contains(tag) {
            if let count = counts.first(where: { $0.value == tag }) {
                result.append(count)
                included.insert(tag)
            }
        }
        return result
    }

    private static func displayText(_ value: String,
                                    fallback: String,
                                    maxLength: Int) -> String {
        MarkdownExportSafety.metadata(value, fallback: fallback, maxLength: maxLength)
    }
}
