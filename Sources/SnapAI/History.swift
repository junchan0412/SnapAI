import Foundation

/// 一条历史记录(一次问答)
struct HistoryEntry: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var date: Date = Date()
    var actionName: String       // 动作名,如「翻译」
    var source: String           // 原始输入文字
    var output: String           // AI 输出
    var provider: String         // 供应商名
    var model: String            // 模型名
    var isFavorite: Bool = false
    var tags: [String] = []

    /// 列表里显示的简短预览
    var preview: String {
        displayBody.snapAITruncated(to: 40)
    }

    var sourceDisplayText: String? {
        source.snapAIHistoryNilIfBlank()
    }

    var outputDisplayText: String? {
        output.snapAIHistoryNilIfBlank()
    }

    var copyableOutputText: String? {
        outputDisplayText
    }

    var reopenSourceText: String? {
        guard !isSourceTruncatedRecord else { return nil }
        return sourceDisplayText
    }

    var canReopen: Bool {
        reopenSourceText != nil
    }

    var reopenHelpText: String {
        if canReopen { return "重新发起" }
        if isSourceTruncatedRecord { return "原文已截断,不能直接重新发起" }
        return "该记录未保存原文"
    }

    var isSourceTruncatedRecord: Bool {
        displayTags.contains(PrivacyHistoryTag.sourceTruncated)
    }

    var isOutputTruncatedRecord: Bool {
        displayTags.contains(PrivacyHistoryTag.outputTruncated)
    }

    var isMetadataOnlyRecord: Bool {
        sourceDisplayText == nil &&
        outputDisplayText == nil &&
        displayTags.contains(PrivacyHistoryTag.metadataOnly)
    }

    var emptyContentPlaceholder: String {
        isMetadataOnlyRecord ? "仅保存元信息,未保存原文与结果" : "无原文或结果"
    }

    var sourceExportText: String {
        sourceDisplayText ?? (isMetadataOnlyRecord ? "仅保存元信息,未保存原文" : "无原文")
    }

    var outputExportText: String {
        outputDisplayText ?? (isMetadataOnlyRecord ? "仅保存元信息,未保存结果" : "无结果")
    }

    var displayActionName: String {
        actionName.snapAIHistoryDisplayText() ?? "未命名动作"
    }

    var displayProviderName: String? {
        provider.snapAIHistoryDisplayText()
    }

    var displayModelName: String? {
        model.snapAIHistoryDisplayText()
    }

    var displayModelFilterName: String {
        displayModelName ?? "未知模型"
    }

    var modelDisplayText: String {
        if let provider = displayProviderName {
            return "\(provider) / \(displayModelFilterName)"
        }
        return displayModelName ?? "未知模型"
    }

    var displayTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags.compactMap({ $0.snapAIHistoryDisplayText() }) {
            guard !seen.contains(tag) else { continue }
            seen.insert(tag)
            result.append(tag)
        }
        return result
    }

    var commandPaletteKeywords: String {
        let metadataValues: [String?] = [
            displayActionName,
            displayProviderName,
            displayModelFilterName,
            displayTags.joined(separator: " ")
        ]
        let contentValues = [
            source.snapAIHistorySearchSnippet(maxLength: 600),
            output.snapAIHistorySearchSnippet(maxLength: 600)
        ]
        return MarkdownExportSafety.keywords(metadataValues + contentValues,
                                             maxLength: 1_300,
                                             partMaxLength: 600)
    }

    var commandPaletteSubtitle: String {
        commandPaletteSubtitle(maxLength: 72)
    }

    func commandPaletteSubtitle(maxLength: Int) -> String {
        var parts = ["历史记录"]
        parts.append(displayActionName)
        parts.append(modelDisplayText)
        parts.append(dateString)
        if isFavorite {
            parts.append("收藏")
        }
        let tagSummary = displayTags
            .prefix(2)
            .map { "#\($0)" }
            .joined(separator: " ")
        if !tagSummary.isEmpty {
            parts.append(tagSummary)
        }
        return parts.joined(separator: " - ").snapAITruncated(to: maxLength)
    }

    var menuTitle: String {
        menuTitle(maxLength: 30)
    }

    func menuTitle(maxLength: Int) -> String {
        let action = actionName.snapAIHistoryDisplayText()
        let prefix = action.map { "[\($0)] " } ?? ""
        let body = displayBody
        let hasSourceOrOutput = !source.snapAIHistoryCollapsed().isEmpty || !output.snapAIHistoryCollapsed().isEmpty
        let title = body.isEmpty || !hasSourceOrOutput ? (action ?? displayActionName) : "\(prefix)\(body)"
        return title.snapAITruncated(to: maxLength)
    }

    private var displayBody: String {
        let sourceTitle = source.snapAIHistoryCollapsed()
        if !sourceTitle.isEmpty { return sourceTitle }
        let outputTitle = output.snapAIHistoryCollapsed()
        if !outputTitle.isEmpty { return outputTitle }
        return displayActionName
    }

    var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    var markdownExport: String {
        let fullDate = ISO8601DateFormatter().string(from: date)
        let actionTitle = displayActionName.snapAIHistoryMarkdownMetadata(fallback: "未命名动作", maxLength: 80)
        let modelText = modelDisplayText.snapAIHistoryMarkdownMetadata(fallback: "未知模型", maxLength: 160)
        let tagText = markdownTagText
        return """
        # \(actionTitle)

        - 时间: \(fullDate)
        - 模型: \(modelText)
        - 收藏: \(isFavorite ? "是" : "否")
        - 标签: \(tagText)

        ## 原文

        \(sourceExportText)

        ## 结果

        \(outputExportText)
        """
    }

    private var markdownTagText: String {
        guard !displayTags.isEmpty else { return "无" }
        return displayTags
            .map { $0.snapAIHistoryMarkdownMetadata(fallback: "未命名标签", maxLength: 48) }
            .joined(separator: ", ")
            .snapAITruncated(to: 240)
    }

    enum CodingKeys: String, CodingKey {
        case id, date, actionName, source, output, provider, model, isFavorite, tags
    }
}

private extension String {
    func snapAIHistoryCollapsed() -> String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func snapAITruncated(to maxLength: Int) -> String {
        guard maxLength > 0 else { return "" }
        guard count > maxLength else { return self }
        guard maxLength > 1 else { return "…" }
        return String(prefix(maxLength - 1)) + "…"
    }

    func snapAIHistoryNilIfBlank() -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func snapAIHistoryDisplayText() -> String? {
        let collapsed = snapAIHistoryCollapsed()
        return collapsed.isEmpty ? nil : collapsed
    }

    func snapAIHistorySearchSnippet(maxLength: Int) -> String? {
        let collapsed = snapAIHistoryCollapsed()
        guard !collapsed.isEmpty else { return nil }
        return collapsed.snapAITruncated(to: maxLength)
    }

    func snapAIHistoryMarkdownMetadata(fallback: String, maxLength: Int) -> String {
        MarkdownExportSafety.metadata(self, fallback: fallback, maxLength: maxLength)
    }
}

struct HistoryFilterCriteria: Equatable {
    static let allActions = "全部动作"
    static let allModels = "全部模型"
    static let allTags = "全部标签"

    var query: String = ""
    var actionFilter: String = Self.allActions
    var modelFilter: String = Self.allModels
    var tagFilter: String = Self.allTags
    var favoriteOnly: Bool = false

    func matches(_ entry: HistoryEntry) -> Bool {
        if favoriteOnly && !entry.isFavorite { return false }
        if let action = Self.normalizedSelectedFacet(actionFilter, allValue: Self.allActions),
           !Self.facetValue(entry.displayActionName, matches: action) {
            return false
        }
        if let model = Self.normalizedSelectedFacet(modelFilter, allValue: Self.allModels),
           !Self.facetValue(entry.displayModelFilterName, matches: model) {
            return false
        }
        if let tag = Self.normalizedSelectedFacet(tagFilter, allValue: Self.allTags),
           !entry.displayTags.contains(where: { Self.facetValue($0, matches: tag) }) {
            return false
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        let searchable = [
            entry.displayActionName,
            entry.source,
            entry.output,
            entry.displayProviderName ?? "",
            entry.displayModelFilterName,
            entry.displayTags.joined(separator: " ")
        ].joined(separator: " ").lowercased()
        let compactSearchable = Self.compactSearchableText(searchable)
        let terms = Self.normalizedQueryTerms(q)
        return terms.allSatisfy { term in
            searchable.contains(term) || compactSearchable.contains(Self.compactSearchableText(term))
        }
    }

    func apply(to entries: [HistoryEntry]) -> [HistoryEntry] {
        entries.filter { matches($0) }
    }

    var summaryText: String {
        var parts: [String] = []
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { parts.append("搜索: \(q)") }
        if favoriteOnly { parts.append("仅收藏") }
        if let action = Self.normalizedSelectedFacet(actionFilter, allValue: Self.allActions) {
            parts.append("动作: \(action)")
        }
        if let model = Self.normalizedSelectedFacet(modelFilter, allValue: Self.allModels) {
            parts.append("模型: \(model)")
        }
        if let tag = Self.normalizedSelectedFacet(tagFilter, allValue: Self.allTags) {
            parts.append("标签: \(tag)")
        }
        return parts.isEmpty ? "全部历史" : parts.joined(separator: " / ")
    }

    static func normalizedQueryTerms(_ query: String) -> [String] {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: isQuerySeparator)
            .map(String.init)
    }

    static func facetValues(_ values: [String]) -> [String] {
        Array(Set(values.compactMap(normalizedFacetValue)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func rankedFacetCounts(_ values: [String]) -> [(value: String, count: Int)] {
        values
            .compactMap(normalizedFacetValue)
            .reduce(into: [String: Int]()) { counts, value in
                counts[value, default: 0] += 1
            }
            .map { (value: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.value.localizedStandardCompare($1.value) == .orderedAscending
            }
    }

    private static func isQuerySeparator(_ character: Character) -> Bool {
        if character.isWhitespace { return true }
        return ["+", "-", "_", "/", "\\", ",", ".", ":", ";", "|", "(", ")", "[", "]", "{", "}", "\"", "'"]
            .contains(character)
    }

    static func normalizedFacetValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedSelectedFacet(_ value: String, allValue: String) -> String? {
        guard value != allValue else { return nil }
        return normalizedFacetValue(value) ?? ""
    }

    private static func compactSearchableText(_ value: String) -> String {
        value
            .lowercased()
            .split(whereSeparator: isQuerySeparator)
            .joined()
    }

    private static func facetValue(_ value: String, matches selected: String) -> Bool {
        normalizedComparableFacetValue(value) == normalizedComparableFacetValue(selected)
    }

    private static func normalizedComparableFacetValue(_ value: String) -> String? {
        normalizedFacetValue(value)?
            .lowercased()
            .split(whereSeparator: isQuerySeparator)
            .joined()
    }
}

struct HistoryCollectionExport {
    var title: String = "SnapAI 历史记录"
    var entries: [HistoryEntry]
    var criteria: HistoryFilterCriteria
    var date: Date = Date()

    var markdown: String {
        let generatedAt = ISO8601DateFormatter().string(from: date)
        let exportTitle = title.snapAIHistoryMarkdownMetadata(fallback: "SnapAI 历史记录", maxLength: 80)
        let criteriaSummary = criteria.summaryText.snapAIHistoryMarkdownMetadata(fallback: "全部历史", maxLength: 240)
        var sections = [
            "# \(exportTitle)",
            "- 导出时间: \(generatedAt)",
            "- 筛选条件: \(criteriaSummary)",
            "- 记录数量: \(entries.count)"
        ].joined(separator: "\n")

        guard !entries.isEmpty else {
            return sections + "\n\n无匹配记录。\n"
        }

        for (index, entry) in entries.enumerated() {
            sections += "\n\n---\n\n"
            let actionTitle = entry.displayActionName.snapAIHistoryMarkdownMetadata(fallback: "未命名动作", maxLength: 80)
            sections += "## \(index + 1). \(actionTitle) - \(entry.dateString)\n\n"
            sections += entry.markdownExport
        }
        return sections
    }
}

struct HistoryContextProfileDraft: Equatable {
    var name: String
    var content: String
    var includedCount: Int
    var skippedCount: Int

    var profile: ContextProfile {
        ContextProfile(name: name, content: content, isEnabled: true)
    }
}

enum HistoryContextProfileBuilder {
    static let defaultMaxEntries = 12
    static let defaultMaxFieldCharacters = 1_500

    static func draft(entries: [HistoryEntry],
                      criteria: HistoryFilterCriteria,
                      date: Date = Date(),
                      maxEntries: Int = defaultMaxEntries,
                      maxFieldCharacters: Int = defaultMaxFieldCharacters) -> HistoryContextProfileDraft? {
        let usableEntries = entries.filter { isUsableForContext($0) }
        guard !usableEntries.isEmpty else { return nil }

        let limitedEntries = Array(usableEntries.prefix(max(1, maxEntries)))
        let skippedCount = entries.count - limitedEntries.count
        let content = contextContent(entries: limitedEntries,
                                     criteria: criteria,
                                     generatedAt: date,
                                     originalCount: entries.count,
                                     skippedCount: skippedCount,
                                     maxFieldCharacters: max(1, maxFieldCharacters))
        return HistoryContextProfileDraft(name: suggestedName(criteria: criteria),
                                          content: content,
                                          includedCount: limitedEntries.count,
                                          skippedCount: skippedCount)
    }

    static func isUsableForContext(_ entry: HistoryEntry) -> Bool {
        entry.sourceDisplayText != nil || entry.outputDisplayText != nil
    }

    private static func suggestedName(criteria: HistoryFilterCriteria) -> String {
        let summary = criteria.summaryText
        guard summary != "全部历史" else {
            return "历史上下文 - 全部历史"
        }
        return "历史上下文 - \(metadata(summary, fallback: "筛选历史", maxLength: 18))"
    }

    private static func contextContent(entries: [HistoryEntry],
                                       criteria: HistoryFilterCriteria,
                                       generatedAt: Date,
                                       originalCount: Int,
                                       skippedCount: Int,
                                       maxFieldCharacters: Int) -> String {
        var lines = [
            "# SnapAI 历史上下文",
            "",
            "- 生成时间: \(ISO8601DateFormatter().string(from: generatedAt))",
            "- 来源筛选: \(metadata(criteria.summaryText, fallback: "全部历史", maxLength: 240))",
            "- 原始记录: \(originalCount)",
            "- 写入记录: \(entries.count)",
            "- 跳过记录: \(skippedCount)",
            "",
            "这些内容来自用户主动选择的历史记录,可作为项目背景、术语、写作偏好或事实依据。"
        ]

        for (index, entry) in entries.enumerated() {
            lines.append("")
            lines.append("## \(index + 1). \(metadata(entry.displayActionName, fallback: "未命名动作", maxLength: 80)) - \(entry.dateString)")
            lines.append("")
            lines.append("- 模型: \(metadata(entry.modelDisplayText, fallback: "未知模型", maxLength: 160))")
            if !entry.displayTags.isEmpty {
                let tags = entry.displayTags
                    .map { "#\(metadata($0, fallback: "未命名标签", maxLength: 48))" }
                    .joined(separator: " ")
                lines.append("- 标签: \(tags)")
            }
            if let source = entry.sourceDisplayText {
                lines.append("")
                lines.append("原文:")
                lines.append(truncateField(source, maxCharacters: maxFieldCharacters))
            }
            if let output = entry.outputDisplayText {
                lines.append("")
                lines.append("结果:")
                lines.append(truncateField(output, maxCharacters: maxFieldCharacters))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func truncateField(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters else { return value }
        return value.snapAITruncated(to: maxCharacters) + "\n[已截断]"
    }

    private static func metadata(_ value: String,
                                 fallback: String,
                                 maxLength: Int) -> String {
        MarkdownExportSafety.metadata(value, fallback: fallback, maxLength: maxLength)
    }
}

extension HistoryEntry {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        date = (try? c.decode(Date.self, forKey: .date)) ?? Date()
        actionName = (try? c.decode(String.self, forKey: .actionName)) ?? ""
        source = (try? c.decode(String.self, forKey: .source)) ?? ""
        output = (try? c.decode(String.self, forKey: .output)) ?? ""
        provider = (try? c.decode(String.self, forKey: .provider)) ?? ""
        model = (try? c.decode(String.self, forKey: .model)) ?? ""
        isFavorite = (try? c.decode(Bool.self, forKey: .isFavorite)) ?? false
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(actionName, forKey: .actionName)
        try c.encode(source, forKey: .source)
        try c.encode(output, forKey: .output)
        try c.encode(provider, forKey: .provider)
        try c.encode(model, forKey: .model)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encode(tags, forKey: .tags)
    }
}
