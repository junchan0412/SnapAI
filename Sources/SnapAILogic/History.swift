import Foundation

private enum HistoryDateFormatting {
    static let compact: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    static let iso8601 = ISO8601DateFormatter()
}

/// 一条历史记录(一次问答)
package struct HistoryEntry: Codable, Identifiable, Equatable {
    package var id: String
    package var date: Date
    package var actionName: String       // 动作名,如「翻译」
    package var source: String           // 原始输入文字
    package var output: String           // AI 输出
    package var provider: String         // 供应商名
    package var model: String            // 模型名
    package var isFavorite: Bool
    package var tags: [String]

    /// 列表里显示的简短预览
    package var preview: String {
        displayBody.snapAITruncated(to: 40)
    }

    package var sourceDisplayText: String? {
        source.snapAIHistoryNilIfBlank()
    }

    package var outputDisplayText: String? {
        output.snapAIHistoryNilIfBlank()
    }

    package var copyableOutputText: String? {
        outputDisplayText
    }

    /// 内容是否长到需要「展开全部」入口(超过卡片预览的截断阈值)。
    package var canExpandContent: Bool {
        let sourceLen = sourceDisplayText?.count ?? 0
        let outputLen = outputDisplayText?.count ?? 0
        return sourceLen > 80 || outputLen > 200
    }

    package var reopenSourceText: String? {
        guard !isSourceTruncatedRecord else { return nil }
        return sourceDisplayText
    }

    package var canReopen: Bool {
        reopenSourceText != nil
    }

    package var reopenHelpText: String {
        if canReopen { return "重新发起" }
        if isSourceTruncatedRecord { return "原文已截断,不能直接重新发起" }
        return "该记录未保存原文"
    }

    package var isSourceTruncatedRecord: Bool {
        displayTags.contains(PrivacyHistoryTag.sourceTruncated)
    }

    package var isOutputTruncatedRecord: Bool {
        displayTags.contains(PrivacyHistoryTag.outputTruncated)
    }

    package var isMetadataOnlyRecord: Bool {
        sourceDisplayText == nil &&
        outputDisplayText == nil &&
        displayTags.contains(PrivacyHistoryTag.metadataOnly)
    }

    package var emptyContentPlaceholder: String {
        isMetadataOnlyRecord ? "仅保存元信息,未保存原文与结果" : "无原文或结果"
    }

    package var sourceExportText: String {
        sourceDisplayText ?? (isMetadataOnlyRecord ? "仅保存元信息,未保存原文" : "无原文")
    }

    package var outputExportText: String {
        outputDisplayText ?? (isMetadataOnlyRecord ? "仅保存元信息,未保存结果" : "无结果")
    }

    package var displayActionName: String {
        actionName.snapAIHistoryDisplayText() ?? "未命名动作"
    }

    package var displayProviderName: String? {
        provider.snapAIHistoryDisplayText()
    }

    package var displayModelName: String? {
        model.snapAIHistoryDisplayText()
    }

    package var displayModelFilterName: String {
        displayModelName ?? "未知模型"
    }

    package var modelDisplayText: String {
        if let provider = displayProviderName {
            return "\(provider) / \(displayModelFilterName)"
        }
        return displayModelName ?? "未知模型"
    }

    package var displayTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags.compactMap({ $0.snapAIHistoryDisplayText() }) {
            guard !seen.contains(tag) else { continue }
            seen.insert(tag)
            result.append(tag)
        }
        return result
    }

    package var commandPaletteKeywords: String {
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

    package var commandPaletteSubtitle: String {
        commandPaletteSubtitle(maxLength: 72)
    }

    package func commandPaletteSubtitle(maxLength: Int) -> String {
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

    package var menuTitle: String {
        menuTitle(maxLength: 30)
    }

    package func menuTitle(maxLength: Int) -> String {
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

    package var dateString: String {
        HistoryDateFormatting.compact.string(from: date)
    }

    package var markdownExport: String {
        let fullDate = HistoryDateFormatting.iso8601.string(from: date)
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

    package enum CodingKeys: String, CodingKey {
        case id, date, actionName, source, output, provider, model, isFavorite, tags
    }

    package init(id: String = UUID().uuidString,
                 date: Date = Date(),
                 actionName: String,
                 source: String,
                 output: String,
                 provider: String,
                 model: String,
                 isFavorite: Bool = false,
                 tags: [String] = []) {
        self.id = id
        self.date = date
        self.actionName = actionName
        self.source = source
        self.output = output
        self.provider = provider
        self.model = model
        self.isFavorite = isFavorite
        self.tags = tags
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

public struct HistoryFilterCriteria: Codable, Equatable {
    public static let allActions = "全部动作"
    public static let allModels = "全部模型"
    public static let allTags = "全部标签"

    public var query: String = ""
    public var actionFilter: String = Self.allActions
    public var modelFilter: String = Self.allModels
    public var tagFilter: String = Self.allTags
    public var favoriteOnly: Bool = false

    public init(query: String = "",
                actionFilter: String = Self.allActions,
                modelFilter: String = Self.allModels,
                tagFilter: String = Self.allTags,
                favoriteOnly: Bool = false) {
        self.query = query
        self.actionFilter = actionFilter
        self.modelFilter = modelFilter
        self.tagFilter = tagFilter
        self.favoriteOnly = favoriteOnly
    }

    public var isDefault: Bool {
        self == HistoryFilterCriteria()
    }

    package func matches(_ entry: HistoryEntry) -> Bool {
        matchesFacets(entry) && matchesQuery(entry)
    }

    package func matchesFacets(_ entry: HistoryEntry) -> Bool {
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
        return true
    }

    package func matchesQuery(_ entry: HistoryEntry) -> Bool {
        matchesQuery(entry, terms: Self.normalizedQueryTerms(query))
    }

    private func matchesQuery(_ entry: HistoryEntry, terms: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        let searchable = [
            entry.displayActionName,
            entry.source,
            entry.output,
            entry.displayProviderName ?? "",
            entry.displayModelFilterName,
            entry.displayTags.joined(separator: " ")
        ].joined(separator: " ").lowercased()
        let compactSearchable = Self.compactSearchableText(searchable)
        return terms.allSatisfy { term in
            searchable.contains(term) || compactSearchable.contains(Self.compactSearchableText(term))
        }
    }

    package func apply(to entries: [HistoryEntry]) -> [HistoryEntry] {
        let terms = Self.normalizedQueryTerms(query)
        return entries.filter { matchesFacets($0) && matchesQuery($0, terms: terms) }
    }

    package var summaryText: String {
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

    package static func normalizedQueryTerms(_ query: String) -> [String] {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: isQuerySeparator)
            .map(String.init)
    }

    package static func facetValues(_ values: [String]) -> [String] {
        Array(Set(values.compactMap(normalizedFacetValue)))
            .sorted(by: facetValuePrecedes)
    }

    package static func rankedFacetCounts(_ values: [String]) -> [(value: String, count: Int)] {
        values
            .compactMap(normalizedFacetValue)
            .reduce(into: [String: Int]()) { counts, value in
                counts[value, default: 0] += 1
            }
            .map { (value: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return facetValuePrecedes($0.value, $1.value)
            }
    }

    private static func facetValuePrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs,
                    options: [.numeric],
                    range: nil,
                    locale: Locale(identifier: "zh_Hans_CN")) == .orderedAscending
    }

    package static func isQuerySeparator(_ character: Character) -> Bool {
        switch character {
        case "+", "-", "_", "/", "\\", ",", ".", ":", ";", "|", "(", ")", "[", "]", "{", "}", "\"", "'":
            return true
        default:
            return character.isWhitespace
        }
    }

    package static func normalizedFacetValue(_ value: String) -> String? {
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

package struct SavedHistoryFilter: Codable, Identifiable, Equatable {
    package var id: String = UUID().uuidString
    package var name: String
    package var criteria: HistoryFilterCriteria
    package var createdAt: Date = Date()
    package var updatedAt: Date = Date()

    package var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名筛选" : name
    }

    package var subtitle: String {
        criteria.summaryText
    }
}

package enum HistorySearch {
    package static func filteredEntries(criteria: HistoryFilterCriteria,
                                memoryEntries: [HistoryEntry],
                                limit: Int,
                                searchStore: (String, Int) -> [HistoryEntry]) -> [HistoryEntry] {
        let query = criteria.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return criteria.apply(to: memoryEntries)
        }

        let memoryByID = Dictionary(memoryEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let storeLimit = max(max(0, limit), memoryEntries.count, 1)
        var seen = Set<String>()
        var candidates: [HistoryEntry] = []

        func append(_ entry: HistoryEntry) {
            guard !seen.contains(entry.id) else { return }
            seen.insert(entry.id)
            candidates.append(entry)
        }

        for entry in searchStore(query, storeLimit) {
            if let current = memoryByID[entry.id] { append(current) }
        }

        // Preserve compact/fallback matching semantics and any unsynced in-memory edits.
        for entry in criteria.apply(to: memoryEntries) {
            append(entry)
        }

        for entry in HistorySemanticSearch.search(query: query,
                                                  entries: memoryEntries,
                                                  limit: storeLimit) {
            append(entry)
        }

        return candidates.filter { criteria.matchesFacets($0) }
    }
}

package enum HistorySemanticSearch {
    private struct Concept {
        var triggers: [String]
        var matches: [(normalized: String, compact: String)]
        var weight: Int

        init(triggers: [String], matches: [String], weight: Int = 10) {
            self.triggers = triggers
            self.matches = matches.map { (normalizedSearchText($0), compactSearchText($0)) }
            self.weight = weight
        }
    }

    private static let concepts: [Concept] = [
        Concept(
            triggers: ["钥匙串", "keychain", "密码", "密钥", "secret", "api key", "apikey", "credential", "credentials"],
            matches: ["钥匙串", "keychain", "password", "secret", "api key", "apikey", "credential", "credentials", "ksec", "secitem"]
        ),
        Concept(
            triggers: ["权限", "授权", "permission", "permissions", "accessibility", "辅助功能", "屏幕录制", "screen recording"],
            matches: ["权限", "授权", "permission", "permissions", "accessibility", "辅助功能", "screen recording", "屏幕录制", "privacy"]
        ),
        Concept(
            triggers: ["签名", "证书", "自签名", "codesign", "certificate", "identity", "公证", "notarization", "gatekeeper"],
            matches: ["签名", "证书", "自签名", "codesign", "certificate", "identity", "designated requirement", "fingerprint", "spctl", "gatekeeper", "notarization"]
        ),
        Concept(
            triggers: ["更新", "升级", "安装", "release", "manifest", "updater", "xattr", "quarantine"],
            matches: ["更新", "升级", "安装", "release", "manifest", "updater", "zip", "sha256", "xattr", "quarantine", "download", "github"]
        ),
        Concept(
            triggers: ["路由", "模型选择", "fallback", "备用", "供应商", "首 token", "first token"],
            matches: ["路由", "模型", "fallback", "备用", "供应商", "provider", "route", "routing", "first token", "首 token", "metrics"]
        ),
        Concept(
            triggers: ["图片", "截图", "视觉", "识图", "vision", "image", "screenshot", "ocr"],
            matches: ["图片", "截图", "视觉", "识图", "vision", "image", "screenshot", "ocr", "screen capture", "屏幕"]
        ),
        Concept(
            triggers: ["写回", "替换", "追加", "剪贴板", "粘贴", "pasteboard", "clipboard", "replace", "append"],
            matches: ["写回", "替换", "追加", "剪贴板", "粘贴", "pasteboard", "clipboard", "replace", "append", "selection"]
        ),
        Concept(
            triggers: ["润色", "改写", "优化表达", "polish", "rewrite", "proofread"],
            matches: ["润色", "改写", "优化表达", "polish", "rewrite", "proofread", "style"]
        ),
        Concept(
            triggers: ["翻译", "中英", "英文", "中文", "translation", "translate", "localization"],
            matches: ["翻译", "中英", "英文", "中文", "translation", "translate", "localization", "language"]
        ),
        Concept(
            triggers: ["历史", "记忆", "上下文", "项目", "知识库", "history", "memory", "context", "project"],
            matches: ["历史", "记忆", "上下文", "项目", "知识库", "history", "memory", "context", "project", "profile", "tag"]
        )
    ]

    package static func search(query: String,
                       entries: [HistoryEntry],
                       limit: Int) -> [HistoryEntry] {
        let activeConcepts = conceptsForQuery(query)
        guard !activeConcepts.isEmpty else { return [] }
        let cappedLimit = max(0, limit)
        guard cappedLimit > 0 else { return [] }

        return entries
            .compactMap { entry -> (entry: HistoryEntry, score: Int)? in
                let score = semanticScore(entry: entry, concepts: activeConcepts)
                guard score >= 10 else { return nil }
                return (entry, score)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.entry.date > $1.entry.date
            }
            .prefix(cappedLimit)
            .map(\.entry)
    }

    private static func conceptsForQuery(_ query: String) -> [Concept] {
        let normalized = normalizedSearchText(query)
        let compact = compactSearchText(query)
        guard !normalized.isEmpty else { return [] }
        return concepts.filter { concept in
            concept.triggers.contains { trigger in
                normalized.contains(normalizedSearchText(trigger)) ||
                compact.contains(compactSearchText(trigger))
            }
        }
    }

    private static func semanticScore(entry: HistoryEntry, concepts: [Concept]) -> Int {
        let text = searchableText(for: entry)
        let compact = text.split(whereSeparator: HistoryFilterCriteria.isQuerySeparator).joined()
        var score = 0
        for concept in concepts {
            let matchedCount = concept.matches.reduce(0) { count, match in
                if text.contains(match.normalized) || compact.contains(match.compact) {
                    return count + 1
                }
                return count
            }
            guard matchedCount > 0 else { continue }
            score += concept.weight + min(matchedCount, 4) * 2
        }
        if entry.isFavorite {
            score += 2
        }
        return score
    }

    private static func searchableText(for entry: HistoryEntry) -> String {
        normalizedSearchText([
            entry.displayActionName,
            entry.source,
            entry.output,
            entry.displayProviderName ?? "",
            entry.displayModelFilterName,
            entry.displayTags.joined(separator: " ")
        ].joined(separator: " "))
    }

    private static func normalizedSearchText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    private static func compactSearchText(_ text: String) -> String {
        normalizedSearchText(text)
            .split(whereSeparator: HistoryFilterCriteria.isQuerySeparator)
            .joined()
    }
}

package struct HistoryCollectionExport {
    package var title: String
    package var entries: [HistoryEntry]
    package var criteria: HistoryFilterCriteria
    package var date: Date

    package var markdown: String {
        let generatedAt = HistoryDateFormatting.iso8601.string(from: date)
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

    package init(title: String = "SnapAI 历史记录",
                 entries: [HistoryEntry],
                 criteria: HistoryFilterCriteria,
                 date: Date = Date()) {
        self.title = title
        self.entries = entries
        self.criteria = criteria
        self.date = date
    }
}

package struct HistoryContextProfileDraft: Equatable {
    package var name: String
    package var content: String
    package var includedCount: Int
    package var skippedCount: Int

    package var profile: ContextProfile {
        ContextProfile(name: name, content: content, isEnabled: true)
    }
}

package enum HistoryContextProfileBuilder {
    package static let defaultMaxEntries = 12
    package static let defaultMaxFieldCharacters = 1_500

    package static func draft(entries: [HistoryEntry],
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

    package static func isUsableForContext(_ entry: HistoryEntry) -> Bool {
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
            "- 生成时间: \(HistoryDateFormatting.iso8601.string(from: generatedAt))",
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
    package init(from decoder: Decoder) throws {
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

    package func encode(to encoder: Encoder) throws {
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
