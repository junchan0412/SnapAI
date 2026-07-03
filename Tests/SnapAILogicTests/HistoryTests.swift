import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox
#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

func testTextDiffSummary() {
    let rows = TextDiff.rows(original: "A\nB\nD", revised: "A\nC\nD\nE")
    let summary = TextDiff.summary(for: rows)
    expect(summary.changed == 1, "counts changed lines")
    expect(summary.inserted == 1, "counts inserted lines")
    expect(summary.deleted == 0, "does not count paired change as delete")
    expect(rows.contains { $0.kind == .unchanged && $0.original == "A" }, "keeps common prefix")
    expect(rows.contains { $0.kind == .unchanged && $0.original == "D" }, "keeps common suffix")
}

func testTextDiffCapsLargePreviewRows() {
    let original = (0..<2_000).map { "old-\($0)" }.joined(separator: "\n")
    let revised = (0..<2_000).map { "new-\($0)" }.joined(separator: "\n")
    let rows = TextDiff.rows(original: original, revised: revised, maxRows: 100)
    expect(rows.count == 100, "caps large diff preview rows")
    expect(rows.allSatisfy { $0.kind == .changed }, "keeps changed rows when capped")
}

func testFollowUpInputBehaviorSupportsMultilineDrafts() {
    expect(FollowUpInputBehavior.placeholder == "追问…",
           "follow-up input keeps a concise placeholder")
    expect(FollowUpInputBehavior.accessibilityLabel == "追问输入框",
           "follow-up input exposes a clear accessibility label")
    expect(FollowUpInputBehavior.helpText.contains("Return 发送追问"),
           "follow-up input help explains submit behavior")
    expect(FollowUpInputBehavior.helpText.contains("Shift+Return"),
           "follow-up input help explains shift return newline behavior")
    expect(FollowUpInputBehavior.helpText.contains("Option+Return"),
           "follow-up input help explains option return newline behavior")
    expect(FollowUpInputBehavior.minHeight >= 30,
           "follow-up input has enough height for comfortable text editing")
    expect(FollowUpInputBehavior.maxHeight > FollowUpInputBehavior.minHeight,
           "follow-up input can grow for multiline drafts")
    expect(FollowUpInputBehavior.returnKeyBehavior(shift: false,
                                                   option: false) == .submit,
           "plain Return submits the follow-up")
    expect(FollowUpInputBehavior.returnKeyBehavior(shift: true,
                                                   option: false) == .insertNewline,
           "Shift-Return inserts a newline in multiline follow-up drafts")
    expect(FollowUpInputBehavior.returnKeyBehavior(shift: false,
                                                   option: true) == .insertNewline,
           "Option-Return inserts a newline in multiline follow-up drafts")
    expect(FollowUpInputBehavior.shouldBrowseHistory(currentText: ""),
           "empty follow-up draft can browse history with arrow keys")
    expect(FollowUpInputBehavior.shouldBrowseHistory(currentText: " \n\t "),
           "whitespace-only follow-up draft can browse history with arrow keys")
    expect(!FollowUpInputBehavior.shouldBrowseHistory(currentText: "继续解释"),
           "non-empty follow-up draft keeps arrow keys for text navigation")
    expect(!FollowUpInputBehavior.shouldBrowseHistory(currentText: "第一行\n第二行"),
           "multiline follow-up draft keeps arrow keys for text navigation")
}

func testFollowUpHistoryStoreNavigatesRecentPromptsSafely() {
    var history = FollowUpHistoryStore(limit: 3)
    expect(history.count == 0, "follow-up history starts empty")
    expect(history.previous() == nil, "empty follow-up history has no previous entry")
    expect(history.next() == nil, "empty follow-up history has no next entry")
    expect(!history.shouldHandleNavigation(currentText: "", direction: .up),
           "empty follow-up history does not intercept up navigation")
    expect(!history.shouldHandleNavigation(currentText: "", direction: .down),
           "empty follow-up history does not intercept down navigation")

    history.record(" 第一条 ")
    history.record("第二条")
    history.record("第三条")
    history.record("第二条")
    expect(history.entries == ["第一条", "第三条", "第二条"],
           "follow-up history deduplicates prompts and moves repeated prompts to the newest position")
    expect(history.count == 3, "follow-up history reports bounded count")

    history.record("第四条")
    expect(history.entries == ["第三条", "第二条", "第四条"],
           "follow-up history keeps only the most recent bounded entries")
    history.record(" \n\t ")
    expect(history.entries == ["第三条", "第二条", "第四条"],
           "follow-up history ignores blank prompts")

    expect(history.shouldHandleNavigation(currentText: "", direction: .up),
           "blank draft can start history navigation with up")
    expect(!history.shouldHandleNavigation(currentText: "", direction: .down),
           "blank draft does not intercept down when no history entry is selected")
    expect(history.previous() == "第四条",
           "first history-up selects the newest prompt")
    expect(history.shouldHandleNavigation(currentText: "第四条", direction: .up),
           "selected history text continues handling up navigation")
    expect(history.shouldHandleNavigation(currentText: "第四条", direction: .down),
           "selected history text continues handling down navigation")
    expect(!history.shouldHandleNavigation(currentText: "第四条 edited", direction: .up),
           "edited history text returns arrow keys to text navigation")
    expect(history.previous() == "第二条",
           "repeated history-up walks to older prompts")
    expect(history.previous() == "第三条",
           "history-up can reach the oldest retained prompt")
    expect(history.previous() == "第三条",
           "history-up stays at the oldest retained prompt")
    expect(history.next() == "第二条",
           "history-down walks toward newer prompts")
    expect(history.next() == "第四条",
           "history-down reaches the newest prompt")
    expect(history.next() == "",
           "history-down from the newest prompt clears back to an empty draft")
    expect(!history.shouldHandleNavigation(currentText: "第四条", direction: .down),
           "cleared history navigation no longer treats old selected text as active")

    history.record("第五条")
    expect(history.selectedText == nil,
           "recording a new prompt resets history navigation")
    expect(history.entries == ["第二条", "第四条", "第五条"],
           "recording a new prompt still enforces the history limit")

    var longHistory = FollowUpHistoryStore(limit: 2)
    let longPrompt = String(repeating: "长", count: FollowUpHistoryStore.maxEntryCharacters + 20)
    longHistory.record(longPrompt)
    expect(longHistory.entries.count == 1,
           "follow-up history stores long prompts as a single bounded entry")
    expect(longHistory.entries[0].count == FollowUpHistoryStore.maxEntryCharacters,
           "follow-up history caps oversized prompt history entries")
    expect(longHistory.entries[0].hasSuffix("..."),
           "follow-up history marks truncated prompt history entries")
    expect(!longHistory.entries[0].contains(String(repeating: "长", count: FollowUpHistoryStore.maxEntryCharacters + 1)),
           "follow-up history drops far-tail content from oversized prompts")
    longHistory.record(longPrompt)
    expect(longHistory.entries.count == 1,
           "follow-up history deduplicates repeated oversized prompts after truncation")
    expect(longHistory.previous() == longHistory.entries[0],
           "follow-up history returns the bounded oversized entry when navigating")

    var zeroLimitHistory = FollowUpHistoryStore(limit: 0)
    expect(zeroLimitHistory.effectiveLimit == 1,
           "follow-up history clamps zero limit to one retained prompt")
    zeroLimitHistory.record("一")
    zeroLimitHistory.record("二")
    expect(zeroLimitHistory.entries == ["二"],
           "follow-up history with zero configured limit still keeps the latest prompt")

    var negativeLimitHistory = FollowUpHistoryStore(limit: -5)
    expect(negativeLimitHistory.effectiveLimit == 1,
           "follow-up history clamps negative limits to one retained prompt")
    negativeLimitHistory.record("旧")
    negativeLimitHistory.record("新")
    expect(negativeLimitHistory.entries == ["新"],
           "follow-up history with negative configured limit still keeps the latest prompt")
}

func testHistoryEntryMarkdownExport() {
    let entry = HistoryEntry(date: Date(timeIntervalSince1970: 0),
                             actionName: "总结",
                             source: "原始内容",
                             output: "总结结果",
                             provider: "OpenAI",
                             model: "gpt-4o-mini",
                             isFavorite: true,
                             tags: ["工作", "摘要"])
    let markdown = entry.markdownExport
    expect(markdown.contains("# 总结"), "exports action as title")
    expect(markdown.contains("- 模型: OpenAI / gpt-4o-mini"), "exports model metadata")
    expect(markdown.contains("- 收藏: 是"), "exports favorite state")
    expect(markdown.contains("- 标签: 工作, 摘要"), "exports tags")
    expect(markdown.contains("## 原文\n\n原始内容"), "exports source")
    expect(markdown.contains("## 结果\n\n总结结果"), "exports output")

    let blank = HistoryEntry(actionName: "空记录",
                             source: " \n ",
                             output: "",
                             provider: "OpenAI",
                             model: "gpt")
    expect(blank.sourceExportText == "无原文", "blank history source exports explicit placeholder")
    expect(blank.outputExportText == "无结果", "blank history output exports explicit placeholder")
    expect(blank.copyableOutputText == nil, "blank history has no copyable output")
    expect(blank.reopenSourceText == nil, "blank history has no source for reopening")
    expect(!blank.canReopen, "blank history cannot reopen as a request")
    expect(blank.reopenHelpText == "该记录未保存原文", "blank history explains why reopening is unavailable")
    expect(!blank.isMetadataOnlyRecord, "blank history without metadata tag is not treated as metadata-only")
    expect(blank.emptyContentPlaceholder == "无原文或结果", "blank non-metadata history uses generic placeholder")
    expect(blank.markdownExport.contains("## 原文\n\n无原文"), "blank source markdown is explicit")
    expect(blank.markdownExport.contains("## 结果\n\n无结果"), "blank output markdown is explicit")

    let metadataOnly = HistoryEntry(actionName: "隐私审计",
                                    source: "",
                                    output: "",
                                    provider: "OpenAI",
                                    model: "gpt",
                                    tags: [PrivacyHistoryTag.metadataOnly])
    expect(metadataOnly.copyableOutputText == nil, "metadata-only history has no copyable output")
    expect(metadataOnly.reopenSourceText == nil, "metadata-only history has no source for reopening")
    expect(!metadataOnly.canReopen, "metadata-only history cannot reopen as a request")
    expect(metadataOnly.reopenHelpText == "该记录未保存原文", "metadata-only history explains why reopening is unavailable")
    expect(metadataOnly.isMetadataOnlyRecord, "metadata-only history is recognized by tag and empty content")
    expect(metadataOnly.emptyContentPlaceholder == "仅保存元信息,未保存原文与结果",
           "metadata-only history explains why content is absent")
    expect(metadataOnly.sourceExportText == "仅保存元信息,未保存原文",
           "metadata-only history export explains missing source")
    expect(metadataOnly.outputExportText == "仅保存元信息,未保存结果",
           "metadata-only history export explains missing output")
    expect(metadataOnly.markdownExport.contains("## 原文\n\n仅保存元信息,未保存原文"),
           "metadata-only markdown explains missing source")
    expect(metadataOnly.markdownExport.contains("## 结果\n\n仅保存元信息,未保存结果"),
           "metadata-only markdown explains missing output")

    let tagged = HistoryEntry(actionName: "总结",
                              source: "原文",
                              output: "结果",
                              provider: "OpenAI",
                              model: "gpt",
                              tags: [" 工作 ", "", "摘要", "工作"])
    expect(tagged.displayTags == ["工作", "摘要"], "history display tags trim, drop blanks and dedupe")
    expect(tagged.reopenSourceText == "原文", "history with source can reopen from display source")
    expect(tagged.canReopen, "history with source can reopen as a request")
    expect(tagged.reopenHelpText == "重新发起", "history with source exposes reopen help text")
    expect(tagged.markdownExport.contains("- 标签: 工作, 摘要"), "history markdown exports display tags")

    let dirtyMetadata = HistoryEntry(actionName: "  总结  ",
                                     source: "原文",
                                     output: "结果",
                                     provider: "  OpenAI  ",
                                     model: "  gpt-4o-mini  ")
    expect(dirtyMetadata.displayActionName == "总结", "history display action trims surrounding whitespace")
    expect(dirtyMetadata.modelDisplayText == "OpenAI / gpt-4o-mini", "history model display trims provider and model")
    expect(dirtyMetadata.markdownExport.contains("# 总结"), "history markdown exports display action")
    expect(dirtyMetadata.markdownExport.contains("- 模型: OpenAI / gpt-4o-mini"),
           "history markdown exports display model metadata")

    let missingModel = HistoryEntry(actionName: "总结",
                                    source: "原文",
                                    output: "结果",
                                    provider: " OpenAI ",
                                    model: " ")
    expect(missingModel.displayModelFilterName == "未知模型", "history model facet uses explicit unknown fallback")
    expect(missingModel.modelDisplayText == "OpenAI / 未知模型", "history model display keeps provider with unknown model")
    expect(missingModel.commandPaletteKeywords.contains("未知模型"), "history command keywords include unknown model fallback")

    let unsafeMetadata = HistoryEntry(actionName: "总结 sk-live-secret-value-1234567890",
                                      source: "正文可保留 sk-live-secret-value-1234567890",
                                      output: "结果",
                                      provider: "OpenAI\nTeam",
                                      model: "gpt|4o `mini` sk-model-secret-value-1234567890",
                                      tags: ["发布 sk-tag-secret-value-1234567890"])
    let unsafeMarkdown = unsafeMetadata.markdownExport
    expect(unsafeMarkdown.contains("# 总结 [REDACTED_KEY]"),
           "history markdown redacts key-like action metadata")
    expect(unsafeMarkdown.contains("- 模型: OpenAI Team / gpt/4o 'mini' [REDACTED_KEY]"),
           "history markdown redacts key-like model metadata and keeps it single-line")
    expect(unsafeMarkdown.contains("- 标签: 发布 [REDACTED_KEY]"),
           "history markdown redacts key-like tag metadata")
    expect(!unsafeMarkdown.contains("sk-model-secret-value-1234567890"),
           "history markdown does not leak key-like model metadata")
    expect(!unsafeMarkdown.contains("sk-tag-secret-value-1234567890"),
           "history markdown does not leak key-like tag metadata")
    expect(unsafeMarkdown.contains("正文可保留 sk-live-secret-value-1234567890"),
           "history markdown preserves user source body content")
}

func testHistoryEntryCompactTitlesForMenus() {
    let longSource = "第一行内容\n\n第二行内容    第三行内容以及一段很长很长的说明文字"
    let entry = HistoryEntry(actionName: "总结",
                             source: longSource,
                             output: "输出内容",
                             provider: "OpenAI",
                             model: "gpt-4o-mini")

    expect(entry.preview == "第一行内容 第二行内容 第三行内容以及一段很长很长的说明文字",
           "history preview collapses whitespace when it fits")
    expect(!entry.menuTitle.contains("\n"), "history menu title is single-line")
    expect(entry.menuTitle.hasPrefix("[总结] "), "history menu title keeps action context")
    expect(entry.menuTitle.count <= 30, "history menu title stays short for menu bar")

    let fallback = HistoryEntry(actionName: "",
                                source: " \n ",
                                output: "用输出作为标题",
                                provider: "OpenAI",
                                model: "gpt-4o-mini")
    expect(fallback.sourceDisplayText == nil, "blank history source has no display text")
    expect(fallback.outputDisplayText == "用输出作为标题", "non-empty history output is displayable")
    expect(fallback.preview == "用输出作为标题", "history preview falls back to output when source is empty")
    expect(fallback.menuTitle == "用输出作为标题", "history menu title falls back to output when source is empty")

    let actionOnly = HistoryEntry(actionName: "空结果动作",
                                  source: "",
                                  output: "",
                                  provider: "OpenAI",
                                  model: "gpt")
    expect(actionOnly.sourceDisplayText == nil, "empty source has no display text")
    expect(actionOnly.outputDisplayText == nil, "empty output has no display text")
    expect(actionOnly.preview == "空结果动作", "history preview falls back to action name when source and output are empty")
    expect(actionOnly.menuTitle == "空结果动作",
           "history menu title avoids duplicating the action when no source or output exists")

    let tiny = HistoryEntry(actionName: "动作",
                            source: "abcdef",
                            output: "",
                            provider: "OpenAI",
                            model: "gpt")
    expect(tiny.menuTitle(maxLength: 1) == "…", "history menu title handles tiny limits")
}

func testHistoryStorePersistsAndSearchesWithFTS() {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("SnapAI-HistoryStore-\(UUID().uuidString).sqlite")
    defer {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }
    let store = HistoryStore(url: url)
    let older = HistoryEntry(id: "older",
                             date: Date(timeIntervalSince1970: 1),
                             actionName: "总结",
                             source: "旧记录",
                             output: "普通输出",
                             provider: "OpenAI",
                             model: "gpt-4o-mini",
                             tags: ["projectA"])
    let newer = HistoryEntry(id: "newer",
                             date: Date(timeIntervalSince1970: 2),
                             actionName: "诊断",
                             source: "release manifest 校验失败",
                             output: "检查签名和 SHA256",
                             provider: "Local",
                             model: "local-model",
                             isFavorite: true,
                             tags: ["发布", "更新"])

    store.replaceAll([older, newer], limit: 20)
    expect(store.load(limit: 20).map(\.id) == ["newer", "older"],
           "history store loads entries by newest first")
    expect(store.search("release SHA256", limit: 20).map(\.id) == ["newer"],
           "history store searches source and output through SQLite FTS")
    expect(store.search("projectA", limit: 20).map(\.id) == ["older"],
           "history store indexes display tags")

    store.delete(id: "newer")
    expect(store.load(limit: 20).map(\.id) == ["older"],
           "history store deletes a single entry from table and index")
    store.deleteAll()
    expect(store.load(limit: 20).isEmpty, "history store clears all entries")
}

func testHistorySearchUsesStoreResultsBeforeFacetFiltering() {
    let summary = HistoryEntry(id: "summary",
                               date: Date(timeIntervalSince1970: 3),
                               actionName: "总结",
                               source: "release manifest",
                               output: "签名校验",
                               provider: "OpenAI",
                               model: "gpt-4o-mini",
                               isFavorite: true,
                               tags: ["发布"])
    let translation = HistoryEntry(id: "translation",
                                   date: Date(timeIntervalSince1970: 2),
                                   actionName: "翻译",
                                   source: "release manifest",
                                   output: "translation",
                                   provider: "OpenAI",
                                   model: "gpt-4o-mini",
                                   tags: ["发布"])
    let staleStoreCopy = HistoryEntry(id: "summary",
                                      date: Date(timeIntervalSince1970: 1),
                                      actionName: "总结",
                                      source: "release manifest",
                                      output: "旧索引副本",
                                      provider: "OpenAI",
                                      model: "gpt-4o-mini",
                                      isFavorite: false,
                                      tags: ["发布"])
    var searchedQuery = ""
    var searchedLimit = 0
    let criteria = HistoryFilterCriteria(query: "release",
                                         actionFilter: "总结",
                                         favoriteOnly: true)
    let filtered = HistorySearch.filteredEntries(
        criteria: criteria,
        memoryEntries: [summary, translation],
        limit: 50,
        searchStore: { query, limit in
            searchedQuery = query
            searchedLimit = limit
            return [translation, staleStoreCopy]
        }
    )

    expect(searchedQuery == "release", "history search sends the query to the local FTS store")
    expect(searchedLimit == 50, "history search asks the store for the configured history limit")
    expect(filtered.map(\.id) == ["summary"],
           "history search applies action and favorite facets after FTS search")
    expect(filtered.first?.output == "签名校验" && filtered.first?.isFavorite == true,
           "history search prefers the live in-memory copy over stale store rows")
}

func testHistorySearchFallsBackToMemoryForCompactMatching() {
    let compactModel = HistoryEntry(id: "compact",
                                    date: Date(timeIntervalSince1970: 0),
                                    actionName: "总结",
                                    source: "普通历史",
                                    output: "结果",
                                    provider: "OpenAI",
                                    model: "gpt-4o-mini")
    var didSearchStore = false
    let filtered = HistorySearch.filteredEntries(
        criteria: HistoryFilterCriteria(query: "gpt4omini"),
        memoryEntries: [compactModel],
        limit: 50,
        searchStore: { _, _ in
            didSearchStore = true
            return []
        }
    )

    expect(didSearchStore, "history search still consults FTS for compact queries")
    expect(filtered.map(\.id) == ["compact"],
           "history search preserves in-memory compact matching when FTS has no direct hit")

    didSearchStore = false
    let noQuery = HistorySearch.filteredEntries(
        criteria: HistoryFilterCriteria(modelFilter: "gpt4omini"),
        memoryEntries: [compactModel],
        limit: 50,
        searchStore: { _, _ in
            didSearchStore = true
            return []
        }
    )
    expect(!didSearchStore, "history search does not hit the store when there is no free-text query")
    expect(noQuery.map(\.id) == ["compact"],
           "history search keeps facet-only filtering in memory")
}

func testHistorySearchIncludesLocalSemanticMatches() {
    let keychain = HistoryEntry(id: "keychain",
                                date: Date(timeIntervalSince1970: 3),
                                actionName: "诊断",
                                source: "Keychain prompts after updating a self-signed certificate",
                                output: "Keep the codesign identity and bundle identifier stable",
                                provider: "OpenAI",
                                model: "gpt-4o-mini",
                                isFavorite: true,
                                tags: ["发布"])
    let routing = HistoryEntry(id: "routing",
                               date: Date(timeIntervalSince1970: 2),
                               actionName: "路由",
                               source: "Fallback provider has a faster first token time",
                               output: "Routing metrics should prefer the reliable model",
                               provider: "OpenAI",
                               model: "gpt-4o-mini",
                               tags: ["AI"])
    let unrelated = HistoryEntry(id: "unrelated",
                                 date: Date(timeIntervalSince1970: 1),
                                 actionName: "翻译",
                                 source: "Translate a short email",
                                 output: "Done",
                                 provider: "OpenAI",
                                 model: "gpt-4o-mini")

    let semantic = HistorySearch.filteredEntries(
        criteria: HistoryFilterCriteria(query: "钥匙串重复授权"),
        memoryEntries: [unrelated, routing, keychain],
        limit: 50,
        searchStore: { _, _ in [] }
    )
    let semanticIDs = semantic.map(\.id)
    expect(semanticIDs == ["keychain"],
           "history semantic search maps Chinese Keychain permission wording to English signing records, got \(semanticIDs)")

    let routed = HistorySearch.filteredEntries(
        criteria: HistoryFilterCriteria(query: "首 token 备用模型"),
        memoryEntries: [unrelated, routing, keychain],
        limit: 50,
        searchStore: { _, _ in [] }
    )
    let routedIDs = routed.map(\.id)
    expect(routedIDs == ["routing"],
           "history semantic search maps first-token fallback wording to routing records, got \(routedIDs)")

    let faceted = HistorySearch.filteredEntries(
        criteria: HistoryFilterCriteria(query: "钥匙串重复授权",
                                        actionFilter: "翻译"),
        memoryEntries: [unrelated, routing, keychain],
        limit: 50,
        searchStore: { _, _ in [] }
    )
    expect(faceted.isEmpty,
           "history semantic matches still respect action/model/tag/favorite facets")
}

func testHistoryFilterCriteriaMatchesMultipleTermsAndFacets() {
    let favorite = HistoryEntry(date: Date(timeIntervalSince1970: 0),
                                actionName: " 总结 ",
                                source: "SnapAI release notes",
                                output: "权限和更新诊断",
                                provider: "OpenAI",
                                model: " gpt-4o-mini ",
                                isFavorite: true,
                                tags: [" 发布 ", "诊断", "发布", ""])
    let other = HistoryEntry(date: Date(timeIntervalSince1970: 1),
                             actionName: "翻译",
                             source: "hello",
                             output: "你好",
                             provider: "Anthropic",
                             model: "claude-sonnet",
                             tags: ["临时"])
    let privacy = HistoryEntry(date: Date(timeIntervalSince1970: 2),
                               actionName: "隐私/审计",
                               source: "联系 [邮箱]",
                               output: "结果",
                               provider: "OpenAI",
                               model: "privacy-model",
                               tags: ["本地脱敏", "隐私预览"])
    let entries = [favorite, other, privacy]

    let queryCriteria = HistoryFilterCriteria(query: "release 诊断")
    expect(queryCriteria.apply(to: entries).map(\.id) == [favorite.id], "matches multi-term history query")
    expect(HistoryFilterCriteria.normalizedQueryTerms("release/诊断+gpt-4o") == ["release", "诊断", "gpt", "4o"],
           "normalizes history query separators")
    expect(HistoryFilterCriteria(query: "release-notes/诊断").apply(to: entries).map(\.id) == [favorite.id],
           "matches history queries separated by punctuation")
    expect(HistoryFilterCriteria(query: "gpt-4o").apply(to: entries).map(\.id) == [favorite.id],
           "matches hyphenated model query terms")
    expect(HistoryFilterCriteria(query: "gpt4omini").apply(to: entries).map(\.id) == [favorite.id],
           "matches compact model query terms")
    expect(HistoryFilterCriteria(query: "发布").apply(to: entries).map(\.id) == [favorite.id],
           "matches normalized display tags in free-text query")
    expect(HistoryFilterCriteria(query: "隐私审计 本地脱敏").apply(to: entries).map(\.id) == [privacy.id],
           "matches compact action and privacy tag terms")
    expect(HistoryFilterCriteria.facetValues([" 总结 ", "", "翻译", "总结", " \n "]) == ["翻译", "总结"],
           "history facet values trim blanks, remove empties, dedupe and sort")
    let facetCounts = HistoryFilterCriteria.rankedFacetCounts([" 项目A ", "项目B", "项目A", "", "项目B", "项目B"])
    expect(facetCounts.map(\.value) == ["项目B", "项目A"],
           "history facet counts sort by count then name")
    expect(facetCounts.map(\.count) == [3, 2],
           "history facet counts trim and filter values")

    let facetCriteria = HistoryFilterCriteria(actionFilter: "总结",
                                              modelFilter: "gpt-4o-mini",
                                              tagFilter: "发布",
                                              favoriteOnly: true)
    expect(facetCriteria.apply(to: entries).map(\.id) == [favorite.id],
           "matches normalized action/model/tag/favorite facets")
    let paddedFacetCriteria = HistoryFilterCriteria(actionFilter: " 总结 ",
                                                    modelFilter: " gpt-4o-mini ",
                                                    tagFilter: " 发布 ")
    expect(paddedFacetCriteria.apply(to: entries).map(\.id) == [favorite.id],
           "normalizes selected history facet filters before matching")

    let missCriteria = HistoryFilterCriteria(query: "release",
                                             actionFilter: "翻译")
    expect(missCriteria.apply(to: entries).isEmpty, "rejects entries outside selected action facet")
    expect(HistoryFilterCriteria(actionFilter: "隐私 审计").apply(to: entries).map(\.id) == [privacy.id],
           "history action facet ignores common separators")
    expect(HistoryFilterCriteria(modelFilter: "gpt4omini").apply(to: entries).map(\.id) == [favorite.id],
           "history model facet ignores common separators")
    expect(HistoryFilterCriteria(tagFilter: "本地-脱敏").apply(to: entries).map(\.id) == [privacy.id],
           "history tag facet ignores common separators for privacy tags")
    expect(facetCriteria.summaryText.contains("仅收藏"), "summarizes favorite filter")
    expect(facetCriteria.summaryText.contains("标签: 发布"), "summarizes tag filter")
}

func testHistoryFilterCriteriaMatchesDisplayFallbacks() {
    let unnamed = HistoryEntry(actionName: " \n ",
                               source: "空动作历史",
                               output: "结果",
                               provider: " OpenAI ",
                               model: " gpt   4o ")
    let missingModel = HistoryEntry(actionName: "总结",
                                    source: "缺少模型",
                                    output: "结果",
                                    provider: " OpenAI ",
                                    model: " ")
    let normal = HistoryEntry(actionName: "总结",
                              source: "普通历史",
                              output: "结果",
                              provider: "OpenAI",
                              model: "gpt")
    let entries = [unnamed, missingModel, normal]

    expect(HistoryFilterCriteria(actionFilter: "未命名动作").apply(to: entries).map(\.id) == [unnamed.id],
           "history action facet matches display fallback names")
    expect(HistoryFilterCriteria(modelFilter: "gpt 4o").apply(to: entries).map(\.id) == [unnamed.id],
           "history model facet matches collapsed display model names")
    expect(HistoryFilterCriteria(modelFilter: "未知模型").apply(to: entries).map(\.id) == [missingModel.id],
           "history model facet matches unknown model fallback")
    expect(HistoryFilterCriteria(modelFilter: "OpenAI").apply(to: entries).isEmpty,
           "history model facet does not treat provider as model fallback")
    expect(HistoryFilterCriteria(query: "未命名动作 gpt 4o").apply(to: entries).map(\.id) == [unnamed.id],
           "history free-text query searches display fallback metadata")
    expect(HistoryFilterCriteria(query: "未知模型").apply(to: entries).map(\.id) == [missingModel.id],
           "history free-text query searches unknown model fallback")
}

func testHistoryCollectionExportMarkdown() {
    let entry = HistoryEntry(date: Date(timeIntervalSince1970: 0),
                             actionName: "总结",
                             source: "原始内容",
                             output: "总结结果",
                             provider: "OpenAI",
                             model: "gpt-4o-mini",
                             tags: ["工作"])
    let criteria = HistoryFilterCriteria(query: "原始",
                                         actionFilter: "总结")
    let export = HistoryCollectionExport(entries: [entry],
                                         criteria: criteria,
                                         date: Date(timeIntervalSince1970: 0))
    let markdown = export.markdown
    expect(markdown.contains("# SnapAI 历史记录"), "exports collection title")
    expect(markdown.contains("- 筛选条件: 搜索: 原始 / 动作: 总结"), "exports filter summary")
    expect(markdown.contains("- 记录数量: 1"), "exports entry count")
    expect(markdown.contains("## 1. 总结 - 01-01 08:00") ||
           markdown.contains("## 1. 总结 - 01-01 00:00") ||
           markdown.contains("## 1. 总结 - 12-31"),
           "exports numbered entry heading with local date")
    expect(markdown.contains("## 原文\n\n原始内容"), "includes entry source")
    expect(markdown.contains("## 结果\n\n总结结果"), "includes entry output")

    let unsafeEntry = HistoryEntry(date: Date(timeIntervalSince1970: 0),
                                   actionName: "总结\n# 注入",
                                   source: "原文\n保留换行",
                                   output: "结果",
                                   provider: "OpenAI\n团队",
                                   model: "gpt|4o\nmini",
                                   tags: ["工作\n项目", "发布`标签", String(repeating: "长", count: 80)])
    let unsafeExport = HistoryCollectionExport(title: "SnapAI\n历史|记录",
                                               entries: [unsafeEntry],
                                               criteria: HistoryFilterCriteria(query: "客户\nA",
                                                                               tagFilter: "工作|项目"),
                                               date: Date(timeIntervalSince1970: 0))
    let unsafeMarkdown = unsafeExport.markdown
    expect(unsafeMarkdown.contains("# SnapAI 历史/记录"), "history export keeps collection title single-line")
    expect(unsafeMarkdown.contains("- 筛选条件: 搜索: 客户 A / 标签: 工作/项目"),
           "history export keeps criteria summary single-line")
    expect(unsafeMarkdown.contains("## 1. 总结 # 注入 -"), "history export keeps entry heading single-line")
    expect(unsafeMarkdown.contains("- 模型: OpenAI 团队 / gpt/4o mini"),
           "history export keeps model metadata single-line and table-safe")
    expect(unsafeMarkdown.contains("- 标签: 工作 项目, 发布'标签"),
           "history export keeps tag metadata single-line and code-safe")
    expect(!unsafeMarkdown.contains("SnapAI\n历史"), "history export does not allow newline injection in title")
    expect(!unsafeMarkdown.contains("总结\n# 注入"), "history export does not allow newline injection in action metadata")
    expect(!unsafeMarkdown.contains("工作\n项目"), "history export does not allow newline injection in tags")
    expect(unsafeMarkdown.contains("## 原文\n\n原文\n保留换行"), "history export preserves source body newlines")

    let secretCriteriaExport = HistoryCollectionExport(
        title: "SnapAI sk-title-secret-value-1234567890",
        entries: [unsafeEntry],
        criteria: HistoryFilterCriteria(query: "sk-query-secret-value-1234567890",
                                        modelFilter: "gpt sk-filter-secret-value-1234567890"),
        date: Date(timeIntervalSince1970: 0)
    )
    let secretCriteriaMarkdown = secretCriteriaExport.markdown
    expect(secretCriteriaMarkdown.contains("# SnapAI [REDACTED_KEY]"),
           "history collection export redacts key-like title metadata")
    expect(secretCriteriaMarkdown.contains("- 筛选条件: 搜索: [REDACTED_KEY] / 模型: gpt [REDACTED_KEY]"),
           "history collection export redacts key-like filter metadata")
    expect(!secretCriteriaMarkdown.contains("sk-title-secret-value-1234567890"),
           "history collection export does not leak title key-like metadata")
    expect(!secretCriteriaMarkdown.contains("sk-query-secret-value-1234567890"),
           "history collection export does not leak query key-like metadata")

    let empty = HistoryCollectionExport(entries: [],
                                        criteria: HistoryFilterCriteria(),
                                        date: Date(timeIntervalSince1970: 0))
    expect(empty.markdown.contains("无匹配记录。"), "explains empty exports")
}

func testHistoryContextProfileBuilderCreatesSafeContextDraft() {
    let date = Date(timeIntervalSince1970: 0)
    let useful = HistoryEntry(date: date,
                              actionName: "润色",
                              source: "SnapAI 是菜单栏 AI 工具。",
                              output: "SnapAI 是一款菜单栏 AI 工具。",
                              provider: "OpenAI",
                              model: "gpt-4o-mini",
                              tags: ["产品", "写作"])
    let outputOnly = HistoryEntry(date: date,
                                  actionName: "总结",
                                  source: "",
                                  output: "用户希望提升替换原文的稳定性。",
                                  provider: "DeepSeek",
                                  model: "deepseek-chat")
    let metadataOnly = HistoryEntry(date: date,
                                    actionName: "隐私审计",
                                    source: "",
                                    output: "",
                                    provider: "OpenAI",
                                    model: "gpt",
                                    tags: [PrivacyHistoryTag.metadataOnly])
    let blank = HistoryEntry(date: date,
                             actionName: "空记录",
                             source: " \n ",
                             output: "",
                             provider: "OpenAI",
                             model: "gpt")
    let criteria = HistoryFilterCriteria(query: "SnapAI",
                                         actionFilter: "润色",
                                         tagFilter: "产品")

    guard let draft = HistoryContextProfileBuilder.draft(entries: [useful, metadataOnly, blank, outputOnly],
                                                         criteria: criteria,
                                                         date: date,
                                                         maxEntries: 5,
                                                         maxFieldCharacters: 19) else {
        expect(false, "creates context draft when at least one history entry has content")
        return
    }

    expect(draft.name.hasPrefix("历史上下文 - 搜索: SnapAI"), "context draft name summarizes active filters")
    expect(draft.includedCount == 2, "context draft includes usable entries")
    expect(draft.skippedCount == 2, "context draft skips metadata-only and blank entries")
    expect(draft.profile.name == draft.name, "context draft creates an enabled context profile")
    expect(draft.profile.isEnabled, "generated context profile is enabled")

    let content = draft.content
    expect(content.contains("# SnapAI 历史上下文"), "context draft has a clear title")
    expect(content.contains("- 来源筛选: 搜索: SnapAI / 动作: 润色 / 标签: 产品"), "context draft records source filters")
    expect(content.contains("- 写入记录: 2"), "context draft records included count")
    expect(content.contains("- 跳过记录: 2"), "context draft records skipped count")
    expect(content.contains("## 1. 润色"), "context draft numbers included entries")
    expect(content.contains("- 模型: OpenAI / gpt-4o-mini"), "context draft includes model metadata")
    expect(content.contains("- 标签: #产品 #写作"), "context draft includes display tags")
    expect(content.contains("原文:\nSnapAI 是菜单栏 AI 工具。"), "context draft includes source text")
    expect(content.contains("[已截断]"), "context draft truncates long fields")
    expect(content.contains("用户希望提升替换原文"), "context draft can include output-only entries")
    expect(!content.contains("仅保存元信息"), "context draft does not copy metadata-only placeholders")
    expect(!content.contains("隐私审计"), "context draft omits metadata-only entries")
    expect(!content.contains("空记录"), "context draft omits blank entries")

    let allHistoryMorning = HistoryContextProfileBuilder.draft(entries: [useful],
                                                               criteria: HistoryFilterCriteria(),
                                                               date: Date(timeIntervalSince1970: 0))
    let allHistoryLater = HistoryContextProfileBuilder.draft(entries: [useful],
                                                             criteria: HistoryFilterCriteria(),
                                                             date: Date(timeIntervalSince1970: 3_600))
    expect(allHistoryMorning?.name == "历史上下文 - 全部历史",
           "all-history context draft uses a stable name")
    expect(allHistoryMorning?.name == allHistoryLater?.name,
           "all-history context draft name does not depend on generation time")

    let limitedDraft = HistoryContextProfileBuilder.draft(entries: [useful, outputOnly, metadataOnly],
                                                          criteria: HistoryFilterCriteria(),
                                                          date: date,
                                                          maxEntries: 1,
                                                          maxFieldCharacters: 1_000)
    expect(limitedDraft?.includedCount == 1, "context draft maxEntries limits included records")
    expect(limitedDraft?.skippedCount == 2, "context draft maxEntries contributes to skipped count")
    expect(limitedDraft?.content.contains("SnapAI 是菜单栏 AI 工具。") == true,
           "context draft maxEntries keeps the first usable record")
    expect(limitedDraft?.content.contains("用户希望提升替换原文") == false,
           "context draft maxEntries omits later usable records")

    expect(HistoryContextProfileBuilder.draft(entries: [metadataOnly, blank],
                                              criteria: HistoryFilterCriteria(),
                                              date: date) == nil,
           "context draft is unavailable when no history content can be written")
}

func testHistoryContextProfileBuilderSanitizesMetadata() {
    let date = Date(timeIntervalSince1970: 0)
    let entry = HistoryEntry(date: date,
                             actionName: "总结\n# 注入|`A`",
                             source: "原文第一行\n原文第二行",
                             output: "结果第一行\n结果第二行",
                             provider: "OpenAI\nProvider|`B`",
                             model: "gpt|4o\nmini sk-live-secret-value-1234567890",
                             tags: ["项目\n# 注入|`Tag`"])
    let criteria = HistoryFilterCriteria(query: "SnapAI\n# 注入|`Q`",
                                         actionFilter: "总结\n# 注入|`A`",
                                         tagFilter: "项目\n# 注入|`Tag`")

    guard let draft = HistoryContextProfileBuilder.draft(entries: [entry],
                                                         criteria: criteria,
                                                         date: date,
                                                         maxEntries: 5,
                                                         maxFieldCharacters: 1_000) else {
        expect(false, "creates context draft for unsafe metadata fixture")
        return
    }

    expect(draft.name.hasPrefix("历史上下文 - 搜索: SnapAI") && draft.name.hasSuffix("..."),
           "context draft name keeps unsafe criteria metadata readable and bounded")
    expect(!draft.name.contains("\n"), "context draft name does not allow newline injection")
    expect(!draft.name.contains("|") && !draft.name.contains("`"),
           "context draft name removes markdown table and code fence metadata characters")

    let content = draft.content
    expect(content.contains("- 来源筛选: 搜索: SnapAI # 注入/'Q' / 动作: 总结 # 注入/'A' / 标签: 项目 # 注入/'Tag'"),
           "context draft source filter metadata is single-line and code-safe")
    expect(content.contains("## 1. 总结 # 注入/'A' - 01-01 08:00") ||
           content.contains("## 1. 总结 # 注入/'A' - 01-01 00:00"),
           "context draft entry heading metadata is single-line and code-safe")
    expect(content.contains("- 模型: OpenAI Provider/'B' / gpt/4o mini [REDACTED_KEY]"),
           "context draft model metadata is sanitized and redacts accidental keys")
    expect(content.contains("- 标签: #项目 # 注入/'Tag'"),
           "context draft tag metadata is single-line and code-safe")
    expect(!content.contains("总结\n# 注入"), "context draft does not allow action metadata newline injection")
    expect(!content.contains("OpenAI\nProvider"), "context draft does not allow model metadata newline injection")
    expect(!content.contains("sk-live-secret-value-1234567890"),
           "context draft does not leak key-like metadata")
    expect(content.contains("原文:\n原文第一行\n原文第二行"),
           "context draft preserves source body newlines")
    expect(content.contains("结果:\n结果第一行\n结果第二行"),
           "context draft preserves output body newlines")
}

func testConversationExportMarkdown() {
    let export = ConversationExport(actionName: "润色",
                                    sourceText: "原文",
                                    outputText: "润色结果",
                                    providerName: "OpenAI",
                                    modelName: "gpt-4o-mini",
                                    elapsed: 1.25,
                                    diagnostics: "route ok",
                                    date: Date(timeIntervalSince1970: 0))
    let markdown = export.markdown
    expect(markdown.contains("# 润色"), "exports action title")
    expect(markdown.contains("## 原文\n\n原文"), "exports source section")
    expect(markdown.contains("## 结果\n\n润色结果"), "exports output section")
    expect(markdown.contains("*模型: OpenAI / gpt-4o-mini | 耗时: 1.2s*"), "exports model and elapsed")
    expect(markdown.contains("## 诊断"), "includes diagnostics section")
    expect(markdown.contains("route ok"), "includes diagnostics text")

    let unsafeDiagnostics = """
    route failed
    Authorization: Bearer sk-live-secret-value-1234567890
    log: /Users/alice/Library/Logs/snapai.log
    ```
    """
    let unsafeExport = ConversationExport(actionName: "润色\n换行",
                                          sourceText: "原文",
                                          outputText: "结果",
                                          providerName: "OpenAI",
                                          modelName: "gpt-4o-mini",
                                          elapsed: 0.5,
                                          diagnostics: unsafeDiagnostics,
                                          date: Date(timeIntervalSince1970: 0))
    let unsafeMarkdown = unsafeExport.markdown
    expect(unsafeMarkdown.contains("# 润色 换行"), "conversation export keeps headings single-line")
    expect(!unsafeMarkdown.contains("sk-live-secret-value-1234567890"), "conversation export redacts diagnostic secrets")
    expect(!unsafeMarkdown.contains("/Users/alice"), "conversation export redacts diagnostic user paths")
    expect(unsafeMarkdown.contains("/Users/[user]/Library/Logs/snapai.log"),
           "conversation export keeps useful diagnostic path suffix")
    expect(unsafeMarkdown.contains("````text"), "conversation export expands diagnostic code fence when needed")

    let protectedExport = ConversationExport(actionName: "提问",
                                             sourceText: "联系 test@example.com",
                                             outputText: "结果包含 sk-live-secret-value-1234567890",
                                             providerName: "OpenAI",
                                             modelName: "gpt-4o-mini",
                                             elapsed: 0.5,
                                             diagnostics: "Privacy Risk: high",
                                             protectsContent: true,
                                             date: Date(timeIntervalSince1970: 0))
    let protectedMarkdown = protectedExport.markdown
    expect(protectedMarkdown.contains("## 隐私保护"),
           "protected conversation export explains why content is omitted")
    expect(protectedMarkdown.contains("因高风险隐私保护,未导出原文。"),
           "protected conversation export replaces source text")
    expect(protectedMarkdown.contains("因高风险隐私保护,未导出结果。"),
           "protected conversation export replaces output text")
    expect(!protectedMarkdown.contains("test@example.com"),
           "protected conversation export omits sensitive source")
    expect(!protectedMarkdown.contains("sk-live-secret-value-1234567890"),
           "protected conversation export omits sensitive output")
    expect(protectedMarkdown.contains("Privacy Risk: high"),
           "protected conversation export still includes safe diagnostics")
}
