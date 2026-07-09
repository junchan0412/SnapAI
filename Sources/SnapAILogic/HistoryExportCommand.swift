import Foundation

public struct HistoryExportCommandInput: Equatable {
    public var displayActionName: String
    public var displayModelFilterName: String
    public var displayTags: [String]
    public var isFavorite: Bool

    public init(displayActionName: String,
                displayModelFilterName: String,
                displayTags: [String],
                isFavorite: Bool) {
        self.displayActionName = displayActionName
        self.displayModelFilterName = displayModelFilterName
        self.displayTags = displayTags
        self.isFavorite = isFavorite
    }
}

public struct HistoryExportCommandCriteria: Equatable {
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

public struct HistoryExportCommandDescriptor: Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: String
    public var criteria: HistoryExportCommandCriteria
}

public enum HistoryExportCommandFactory {
    public static func descriptors(for history: [HistoryExportCommandInput],
                                   facetLimit: Int = 8) -> [HistoryExportCommandDescriptor] {
        guard !history.isEmpty else { return [] }
        var usedIDs: Set<String> = ["history-copy-markdown", "history-copy-favorites-markdown"]
        var result: [HistoryExportCommandDescriptor] = [
            HistoryExportCommandDescriptor(
                id: "history-copy-markdown",
                title: "复制全部历史",
                subtitle: "\(history.count) 条记录,Markdown",
                systemImage: "doc.on.clipboard",
                keywords: MarkdownExportSafety.keywords(["history export copy markdown all 历史 导出 复制 全部"]),
                criteria: HistoryExportCommandCriteria()
            )
        ]

        for action in rankedFacetCounts(history.map(\.displayActionName), fallback: "未命名动作").prefix(facetLimit) {
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
                criteria: HistoryExportCommandCriteria(actionFilter: action.value)
            ))
        }

        for model in rankedFacetCounts(history.map(\.displayModelFilterName), fallback: "未知模型").prefix(facetLimit) {
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
                criteria: HistoryExportCommandCriteria(modelFilter: model.value)
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
                criteria: HistoryExportCommandCriteria(tagFilter: tag.value)
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
                criteria: HistoryExportCommandCriteria(favoriteOnly: true)
            ))
        }

        return result
    }

    private static func prioritizedTagCounts(from history: [HistoryExportCommandInput],
                                             facetLimit: Int) -> [(value: String, count: Int)] {
        let counts = rankedFacetCounts(history.flatMap { dedupedFacetValues($0.displayTags, fallback: nil) }, fallback: nil)
        var result = Array(counts.prefix(facetLimit))
        var included = Set(result.map(\.value))
        for tag in prioritizedPrivacyTags where !included.contains(tag) {
            if let count = counts.first(where: { $0.value == tag }) {
                result.append(count)
                included.insert(tag)
            }
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

    private static let prioritizedPrivacyTags = [
        "本地脱敏",
        "脱敏命中",
        "脱敏规则异常",
        "隐私风险高",
        "隐私风险中",
        "隐私预览",
        "仅元信息"
    ]
}
