import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox
#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

func testBaseURLNormalization() {
    expect(AIClient.normalizedBase("api.openai.com", proto: .openAI) == "https://api.openai.com/v1",
           "adds https and /v1")
    expect(AIClient.normalizedBase("https://api.deepseek.com/v1/chat/completions", proto: .openAI) == "https://api.deepseek.com/v1",
           "strips method suffix")
    expect(AIClient.normalizedBase("http://localhost:11434", proto: .openAI) == "http://localhost:11434/v1",
           "keeps local http")
}

func testPromptRender() {
    var action = AIAction()
    action.prompt = "翻译: {{lang}}\n{{text}}"
    action.isTranslation = true
    action.targetLanguage = .english
    expect(action.render(text: "你好") == "翻译: 翻译成自然流畅的英语\n你好", "renders text and language placeholders")
}

func testActionPipelineDiagnostic() {
    let settings = AppSettings()
    settings.applyWorkMode(.privacy)
    var action = AIAction.defaults()[2]
    action.saveHistory = false
    action.providerID = "local-provider"
    action.modelOverride = "local-chat"

    let diagnostic = ActionPipelineDiagnostic.make(action: action,
                                                   settings: settings,
                                                   hasImage: true)
    expect(diagnostic.inputPolicy == "text+image",
           "pipeline diagnostic records image input")
    expect(diagnostic.privacyPolicy == "preview+local-redaction+no-history",
           "pipeline diagnostic summarizes privacy stages")
    expect(diagnostic.outputPolicy == "replace-confirmation",
           "pipeline diagnostic records replacement confirmation output")
    expect(diagnostic.modelPolicy == "action-override",
           "pipeline diagnostic records action model overrides")
    expect(diagnostic.summaryLines.contains("Pipeline Privacy: preview+local-redaction+no-history"),
           "pipeline diagnostic renders shareable summary lines")

    action.providerID = nil
    action.modelOverride = nil
    action.saveHistory = true
    let localFirst = ActionPipelineDiagnostic.make(action: action,
                                                   settings: settings,
                                                   hasImage: false)
    expect(localFirst.modelPolicy == "auto-route-local-first",
           "pipeline diagnostic records privacy-mode local-first routing")
    expect(localFirst.privacyPolicy.contains("history-metadata-only"),
           "pipeline diagnostic records metadata-only history")

    let capturedInput = ActionPipelineDiagnostic.make(action: action,
                                                      settings: settings,
                                                      hasImage: false,
                                                      captureMethod: .accessibility,
                                                      sourceKind: .codeEditor)
    expect(capturedInput.inputPolicy == "text+capture-accessibility+source-code-editor",
           "pipeline diagnostic records selected-text capture method")

    let serviceInput = ActionPipelineDiagnostic.make(action: action,
                                                     settings: settings,
                                                     hasImage: false,
                                                     captureMethod: .service)
    expect(serviceInput.inputPolicy == "text+capture-service",
           "pipeline diagnostic records text delivered by the macOS Services menu")
}

func testAIActionSanitizesImportedConfiguration() {
    var action = AIAction()
    action.id = "duplicate-action"
    action.name = String(repeating: "动作", count: 80)
    action.icon = String(repeating: "i", count: AIAction.maxIconLength + 10)
    action.group = String(repeating: "分组", count: 80)
    action.prompt = String(repeating: "p", count: AIAction.maxPromptLength + 100)
    action.thinkingBudget = -100
    action.providerID = " provider "
    action.modelOverride = " model "

    var duplicate = action
    duplicate.name = "Second"
    duplicate.thinkingBudget = AIAction.thinkingBudgetRange.upperBound + 100

    let sanitized = AppSettings.sanitizedImportedActions([action, duplicate])
    expect(sanitized.count == 2, "keeps imported actions after sanitizing")
    expect(Set(sanitized.map(\.id)).count == 2, "assigns unique action ids")
    expect(sanitized.first?.name.count == AIAction.maxNameLength, "caps action names")
    expect(sanitized.first?.icon.count == AIAction.maxIconLength, "caps action icons")
    expect(sanitized.first?.group.count == AIAction.maxGroupLength, "caps action groups")
    expect(sanitized.first?.prompt.count == AIAction.maxPromptLength, "caps action prompts")
    expect(sanitized.first?.thinkingBudget == AIAction.thinkingBudgetRange.lowerBound,
           "clamps low thinking budgets")
    expect(sanitized.dropFirst().first?.thinkingBudget == AIAction.thinkingBudgetRange.upperBound,
           "clamps high thinking budgets")
    expect(sanitized.first?.providerID == "provider", "trims action provider ids")
    expect(sanitized.first?.modelOverride == "model", "trims action model overrides")
    action.modelOverride = String(repeating: "m", count: AppSettings.importedModelNameLimit + 20)
    expect(AppSettings.sanitizedImportedActions([action]).first?.modelOverride?.count == AppSettings.importedModelNameLimit,
           "caps action model overrides")
    expect(!AppSettings.sanitizedImportedActions([]).isEmpty, "restores default actions when an import contains none")
}

func testActionTemplateLibraryBuiltInsAreShareable() {
    let templates = ActionTemplateLibrary.builtIns
    expect(templates.count >= 5, "ships a useful built-in action template catalog")
    expect(templates.contains { $0.title == "代码审查" && $0.category == "代码" },
           "built-in catalog includes code review")
    expect(templates.allSatisfy { !$0.action.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
           "built-in templates include prompts")
    expect(templates.allSatisfy { $0.action.hotKey == nil },
           "built-in templates do not reserve global shortcuts")
}

func testActionTemplateLibraryExportsPortableBundle() {
    var action = AIAction(name: "团队润色", icon: "wand.and.stars",
                          group: "写作",
                          prompt: "请润色:\n\n{{text}}",
                          hotKey: HotKeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(optionKey)))
    action.providerID = "private-provider-id"
    action.modelOverride = "private-model-name"

    guard let data = try? ActionTemplateLibrary.exportBundleData(actions: [action],
                                                                 exportedAt: Date(timeIntervalSince1970: 0)),
          let json = String(data: data, encoding: .utf8) else {
        expect(false, "exports action template bundle")
        return
    }
    expect(!json.contains("private-provider-id"), "shared action bundle omits provider ids")
    expect(!json.contains("private-model-name"), "shared action bundle omits model overrides")
    expect(!json.contains("keyCode"), "shared action bundle omits hotkeys")

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let bundle = try? decoder.decode(ActionTemplateBundle.self, from: data),
          let exported = bundle.templates.first?.action else {
        expect(false, "exported action bundle decodes")
        return
    }
    expect(bundle.schemaVersion == ActionTemplateBundle.currentSchemaVersion,
           "exported action bundle records schema version")
    expect(exported.hotKey == nil, "exported template clears hotkey")
    expect(exported.providerID == nil, "exported template clears provider override")
    expect(exported.modelOverride == nil, "exported template clears model override")
}

func testActionTemplateLibraryImportsAndInstallsSafely() {
    var imported = AIAction(name: "润色", icon: "wand.and.stars",
                            group: "写作",
                            prompt: "请润色:\n\n{{text}}",
                            hotKey: HotKeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(optionKey)))
    imported.id = "existing-id"
    imported.providerID = "provider"
    imported.modelOverride = "model"

    let legacyData = try? JSONEncoder().encode([imported])
    guard let data = legacyData,
          let decoded = try? ActionTemplateLibrary.importedActions(from: data),
          let firstDecoded = decoded.first else {
        expect(false, "imports legacy action arrays")
        return
    }
    expect(firstDecoded.hotKey == nil, "imported templates clear external hotkeys")
    expect(firstDecoded.providerID == nil, "imported templates clear provider overrides")
    expect(firstDecoded.modelOverride == nil, "imported templates clear model overrides")

    var existing = AIAction(name: "润色", icon: "wand.and.stars", prompt: "{{text}}")
    existing.id = "existing-id"
    let installed = ActionTemplateLibrary.installedActions(from: decoded,
                                                           existingActions: [existing])
    expect(installed.first?.name == "润色 2", "installing templates avoids duplicate action names")
    expect(installed.first?.id != "existing-id", "installing templates avoids duplicate action ids")
}

func testDefaultPolishActionConfirmsReplacement() {
    let polish = AIAction.defaults().first { $0.name == "润色" }
    expect(polish?.replaceByDefault == true, "polish action enters replacement confirmation by default")
}

func testSettingsModelClearsWhenActiveProviderHasNoEnabledModels() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "disabled-model", enabled: false)])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "disabled-model"

    expect(settings.model.isEmpty, "settings.model is empty when active provider has no enabled models")
    expect(settings.modelSelectionTitle == "选择模型", "model selector title explains missing enabled model")
}

func testAppSettingsAddHistoryCanStoreMetadataOnly() {
    let settings = AppSettings()
    settings.historyContentStorage = .metadataOnly
    settings.addHistory(action: "润色",
                        source: "敏感原文 test@example.com",
                        output: "敏感结果 sk-secret-value",
                        provider: "OpenAI",
                        model: "gpt",
                        tags: ["本地脱敏", "本地脱敏", " "])
    let entry = settings.history.first
    expect(entry?.source == "", "metadata-only history omits source text")
    expect(entry?.output == "", "metadata-only history omits output text")
    expect(entry?.displayTags == ["本地脱敏", "仅元信息"],
           "metadata-only history preserves privacy tags and marks metadata-only storage")
    expect(entry?.markdownExport.contains("敏感原文") == false,
           "metadata-only history markdown does not export source text")
    expect(entry?.markdownExport.contains("敏感结果") == false,
           "metadata-only history markdown does not export output text")
}

func testAppSettingsAddHistoryCanOverrideStorageForOneEntry() {
    let settings = AppSettings()
    settings.historyContentStorage = .full
    settings.addHistory(action: "提问",
                        source: "高风险原文 test@example.com",
                        output: "高风险结果 sk-secret-value",
                        provider: "OpenAI",
                        model: "gpt",
                        tags: ["隐私风险高"],
                        contentStorage: .metadataOnly)

    guard let protected = settings.history.first else {
        expect(false, "per-entry protected history is stored")
        return
    }
    expect(settings.historyContentStorage == .full,
           "per-entry history storage override does not change the global setting")
    expect(protected.source == "", "per-entry metadata-only override omits source text")
    expect(protected.output == "", "per-entry metadata-only override omits output text")
    expect(protected.displayTags == ["隐私风险高", "仅元信息"],
           "per-entry metadata-only override marks the history record")
    expect(!protected.markdownExport.contains("test@example.com"),
           "per-entry metadata-only override keeps sensitive source out of markdown export")
    expect(!protected.markdownExport.contains("sk-secret-value"),
           "per-entry metadata-only override keeps sensitive output out of markdown export")

    settings.addHistory(action: "总结",
                        source: "普通原文",
                        output: "普通结果",
                        provider: "OpenAI",
                        model: "gpt")
    expect(settings.history.first?.source == "普通原文",
           "ordinary history keeps full source when no per-entry override is supplied")
    expect(settings.history.first?.output == "普通结果",
           "ordinary history keeps full output when no per-entry override is supplied")
}

func testAppSettingsAddHistoryTruncatesLargeContentAndTags() {
    let settings = AppSettings()
    let source = "SOURCE-START " + String(repeating: "s", count: AppSettings.historySourceCharacterLimit + 200) + " SOURCE-END"
    let output = "OUTPUT-START " + String(repeating: "o", count: AppSettings.historyOutputCharacterLimit + 200) + " OUTPUT-END"
    let longTag = String(repeating: "标签", count: AppSettings.historyTagCharacterLimit)
    let tags = ["项目", "项目", " "] + (0..<(AppSettings.historyTagLimit + 5)).map { "标签\($0)" } + [longTag]

    settings.addHistory(action: String(repeating: "动作", count: 80),
                        source: source,
                        output: output,
                        provider: String(repeating: "Provider", count: 30),
                        model: String(repeating: "model", count: 80),
                        tags: tags)

    guard let entry = settings.history.first else {
        expect(false, "history entry is stored")
        return
    }

    expect(entry.source.count == AppSettings.historySourceCharacterLimit,
           "history source is capped to the configured storage limit")
    expect(entry.output.count == AppSettings.historyOutputCharacterLimit,
           "history output is capped to the configured storage limit")
    expect(entry.source.contains("[SnapAI: 历史记录已截断"), "truncated source includes an explicit marker")
    expect(entry.output.contains("[SnapAI: 历史记录已截断"), "truncated output includes an explicit marker")
    expect(!entry.source.contains("SOURCE-END"), "truncated source drops far-tail content")
    expect(!entry.output.contains("OUTPUT-END"), "truncated output drops far-tail content")
    expect(entry.displayTags.contains(PrivacyHistoryTag.sourceTruncated), "history tags source truncation")
    expect(entry.displayTags.contains(PrivacyHistoryTag.outputTruncated), "history tags output truncation")
    expect(entry.displayTags.count <= AppSettings.historyTagLimit, "history tags are capped")
    expect(!entry.canReopen, "truncated source history cannot be reopened as a full request")
    expect(entry.reopenHelpText == "原文已截断,不能直接重新发起",
           "truncated source history explains why reopen is disabled")
    expect(entry.copyableOutputText?.contains("[SnapAI: 历史记录已截断") == true,
           "copyable truncated output carries the truncation marker")
    expect(entry.actionName.count == AIAction.maxNameLength, "history action names are capped")
    expect(entry.provider.count == AppSettings.importedProviderNameLimit, "history provider names are capped")
    expect(entry.model.count == AppSettings.importedModelNameLimit, "history model names are capped")
}

func testAppSettingsUpdateHistoryTagsSanitizesManualTags() {
    let settings = AppSettings()
    settings.addHistory(action: "总结",
                        source: "原文",
                        output: "结果",
                        provider: "OpenAI",
                        model: "gpt")
    guard let id = settings.history.first?.id else {
        expect(false, "history entry is available for tag update")
        return
    }

    let longTag = String(repeating: "L", count: AppSettings.historyTagCharacterLimit + 10)
    let tags = [" 项目 ", "项目", "", longTag] + (0..<(AppSettings.historyTagLimit + 5)).map { "标签\($0)" }
    settings.updateHistoryTags(id: id, tags: tags)
    let displayTags = settings.history.first?.displayTags ?? []

    expect(displayTags.first == "项目", "manual history tags trim whitespace")
    expect(displayTags.filter { $0 == "项目" }.count == 1, "manual history tags dedupe repeated values")
    expect(displayTags.contains(String(repeating: "L", count: AppSettings.historyTagCharacterLimit)),
           "manual history tags cap long labels")
    expect(displayTags.count == AppSettings.historyTagLimit, "manual history tags are capped")
}

func testSettingsDecodeSanitizesStoredHistory() {
    var first = HistoryEntry(actionName: String(repeating: "动作", count: 80),
                             source: "SOURCE " + String(repeating: "s", count: AppSettings.historySourceCharacterLimit + 20),
                             output: "OUTPUT " + String(repeating: "o", count: AppSettings.historyOutputCharacterLimit + 20),
                             provider: String(repeating: "Provider", count: 30),
                             model: String(repeating: "model", count: 80),
                             tags: ["项目", "项目", " "] + (0..<(AppSettings.historyTagLimit + 10)).map { "标签\($0)" })
    first.id = "duplicate-history"
    var second = HistoryEntry(actionName: "Second",
                              source: "second source",
                              output: "second output",
                              provider: "Provider",
                              model: "model",
                              tags: ["second"])
    second.id = "duplicate-history"
    struct LegacyHistorySettingsPayload: Encodable {
        var history: [HistoryEntry]
        var historyLimit: Int
    }

    let legacyPayload = LegacyHistorySettingsPayload(history: [first, second],
                                                     historyLimit: 50_000)
    guard let data = try? JSONEncoder().encode(legacyPayload),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "legacy settings history decode succeeds")
        return
    }

    expect(decoded.historyLimit == AppSettings.importedHistoryLimitRange.upperBound,
           "settings decode clamps oversized history limits")
    expect(decoded.history.count == 2, "settings decode keeps available history within the capped limit")
    expect(Set(decoded.history.map(\.id)).count == 2, "settings decode assigns unique history ids")
    guard let entry = decoded.history.first else {
        expect(false, "decoded history has first entry")
        return
    }
    expect(entry.source.count == AppSettings.historySourceCharacterLimit,
           "settings decode caps stored history source")
    expect(entry.output.count == AppSettings.historyOutputCharacterLimit,
           "settings decode caps stored history output")
    expect(entry.displayTags.contains(PrivacyHistoryTag.sourceTruncated),
           "settings decode tags truncated history source")
    expect(entry.displayTags.contains(PrivacyHistoryTag.outputTruncated),
           "settings decode tags truncated history output")
    expect(entry.displayTags.count <= AppSettings.historyTagLimit,
           "settings decode caps stored history tags")
    expect(!entry.canReopen, "settings decode prevents reopening truncated stored source")
    expect(entry.actionName.count == AIAction.maxNameLength,
           "settings decode caps stored history action names")
    expect(entry.provider.count == AppSettings.importedProviderNameLimit,
           "settings decode caps stored history provider names")
    expect(entry.model.count == AppSettings.importedModelNameLimit,
           "settings decode caps stored history model names")
}

func testSettingsClampsStoredPanelDimensions() {
    expect(AppSettings.clampedPanelWidth(.nan) == AppSettings.defaultPanelWidth,
           "panel width clamp falls back for NaN values")
    expect(AppSettings.clampedPanelHeight(.infinity) == AppSettings.defaultPanelHeight,
           "panel height clamp falls back for infinite values")
    expect(AppSettings.clampedPanelWidth(1) == AppSettings.importedPanelWidthRange.lowerBound,
           "panel width clamp enforces minimum usable result window width")
    expect(AppSettings.clampedPanelHeight(1) == AppSettings.importedPanelHeightRange.lowerBound,
           "panel height clamp enforces minimum usable result window height")
    expect(AppSettings.clampedPanelWidth(9_999) == AppSettings.importedPanelWidthRange.upperBound,
           "panel width clamp enforces maximum usable result window width")
    expect(AppSettings.clampedPanelHeight(9_999) == AppSettings.importedPanelHeightRange.upperBound,
           "panel height clamp enforces maximum usable result window height")

    let settings = AppSettings()
    settings.panelWidth = -800
    settings.panelHeight = 20_000
    guard let data = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "settings panel dimension decode succeeds")
        return
    }

    expect(decoded.panelWidth == AppSettings.importedPanelWidthRange.lowerBound,
           "settings decode clamps undersized stored result window width")
    expect(decoded.panelHeight == AppSettings.importedPanelHeightRange.upperBound,
           "settings decode clamps oversized stored result window height")
}

func testSettingsCodablePreservesRoutingAndHistoryPreferences() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Provider", apiProtocol: .openAI,
                              baseURL: "https://example.test/v1",
                              apiKey: "secret",
                              models: [AIModelEntry(name: "gpt-4o-mini")])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "gpt-4o-mini"
    settings.routingPreference = .quality
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = true
    settings.historyContentStorage = .metadataOnly
    settings.actions[0].saveHistory = false
    settings.history = [
        HistoryEntry(actionName: "总结",
                     source: "不应写入设置 JSON 的原文",
                     output: "不应写入设置 JSON 的结果",
                     provider: "Provider",
                     model: "gpt-4o-mini")
    ]

    guard let data = try? JSONEncoder().encode(settings),
          let json = String(data: data, encoding: .utf8),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "settings encode/decode succeeds")
        return
    }
    expect(decoded.routingPreference == .quality, "preserves routing preference")
    expect(decoded.autoRouteEnabled, "preserves auto route setting")
    expect(decoded.fallbackEnabled, "preserves fallback setting")
    expect(decoded.historyContentStorage == .metadataOnly, "preserves history content storage preference")
    expect(decoded.actions.first?.saveHistory == false, "preserves action history preference")
    expect(decoded.providers.first?.apiKey == "", "does not persist provider api key in JSON")
    expect(decoded.history.isEmpty, "new settings JSON no longer carries history entries")
    expect(!json.contains("不应写入设置 JSON"),
           "new settings JSON omits history source and output content")
}

func testSettingsExportConfigurationOmitsSecretsAndHistory() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Provider", apiProtocol: .openAI,
                              baseURL: "https://example.test/v1",
                              apiKey: "sk-proj-export-secret-1234567890",
                              models: [AIModelEntry(name: "gpt-4o-mini")])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "gpt-4o-mini"
    settings.history = [
        HistoryEntry(actionName: "总结",
                     source: "敏感原文",
                     output: "敏感结果",
                     provider: "Provider",
                     model: "gpt-4o-mini")
    ]
    settings.historyContentStorage = .metadataOnly
    settings.actionUsageCounts = ["敏感动作统计": 42]
    settings.panelWidth = 999
    settings.panelHeight = 777
    settings.iCloudSyncEnabled = true
    settings.onboardingDone = false

    guard let data = settings.exportConfigurationData(),
          let exported = try? JSONDecoder().decode(AppSettings.self, from: data),
          let json = String(data: data, encoding: .utf8) else {
        expect(false, "settings export configuration succeeds")
        return
    }

    expect(!json.contains("sk-proj-export-secret-1234567890"), "exported config omits provider api key")
    expect(!json.contains("敏感原文"), "exported config omits history source")
    expect(!json.contains("敏感结果"), "exported config omits history output")
    expect(!json.contains("敏感动作统计"), "exported config omits action usage statistics")
    expect(exported.providers.first?.apiKey == "", "exported config decodes with empty api key")
    expect(exported.history.isEmpty, "exported config clears history")
    expect(exported.actionUsageCounts.isEmpty, "exported config clears action usage statistics")
    expect(exported.panelWidth == 420 && exported.panelHeight == 360,
           "exported config resets window dimensions")
    expect(!exported.iCloudSyncEnabled, "exported config does not enable iCloud sync on import")
    expect(exported.historyContentStorage == .metadataOnly, "exported config preserves history content storage preference")
    expect(exported.onboardingDone, "exported config marks onboarding as done")
}

func testSettingsSanitizesStoredActionUsageCounts() {
    var counts: [String: Int] = [
        " 润色 ": 2,
        "润色": 3,
        "": 99,
        "负数": -1,
        "零": 0,
        String(repeating: "长", count: AIAction.maxNameLength + 20): AppSettings.importedActionUsageCountRange.upperBound + 100
    ]
    for index in 0..<(AppSettings.importedActionUsageLimit + 5) {
        counts["动作\(index)"] = 1
    }

    let sanitized = AppSettings.sanitizedStoredActionUsageCounts(counts)

    expect(sanitized.count == AppSettings.importedActionUsageLimit,
           "settings caps stored action usage count entries")
    expect(sanitized["润色"] == 5,
           "settings merges stored action usage names after trimming")
    expect(!sanitized.keys.contains(""),
           "settings drops blank stored action usage names")
    expect(!sanitized.keys.contains("负数") && !sanitized.keys.contains("零"),
           "settings drops non-positive stored action usage counts")
    expect(sanitized.keys.contains(String(repeating: "长", count: AIAction.maxNameLength)),
           "settings caps stored action usage names")
    expect(sanitized[String(repeating: "长", count: AIAction.maxNameLength)] == AppSettings.importedActionUsageCountRange.upperBound,
           "settings caps oversized stored action usage counts")

    let settings = AppSettings()
    settings.actionUsageCounts = counts
    guard let data = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "settings action usage decode succeeds")
        return
    }
    expect(decoded.actionUsageCounts == AppSettings.sanitizedStoredActionUsageCounts(counts),
           "settings decode sanitizes stored action usage counts")
}

func testSettingsRecordActionUsageUsesSafeBounds() {
    let settings = AppSettings()
    let longName = String(repeating: "A", count: AIAction.maxNameLength + 20)
    settings.recordActionUsage(actionName: " \(longName) ")
    expect(settings.actionUsageCounts[String(repeating: "A", count: AIAction.maxNameLength)] == 1,
           "record action usage trims and caps action names")

    settings.actionUsageCounts["溢出"] = AppSettings.importedActionUsageCountRange.upperBound
    settings.recordActionUsage(actionName: "溢出")
    expect(settings.actionUsageCounts["溢出"] == AppSettings.importedActionUsageCountRange.upperBound,
           "record action usage does not exceed the stored usage cap")

    settings.actionUsageCounts["负数"] = -100
    settings.recordActionUsage(actionName: "负数")
    expect(settings.actionUsageCounts["负数"] == 1,
           "record action usage recovers from negative legacy counts")

    settings.recordActionUsage(actionName: " \n ")
    expect(settings.actionUsageCounts["未命名动作"] == 1,
           "record action usage falls back for blank action names")
}

func testSettingsImportProvidersIgnorePlaintextKeys() {
    var imported = AIProvider(name: "Imported", apiProtocol: .openAI,
                              baseURL: "https://imported.test/v1",
                              apiKey: "sk-imported-plaintext-secret",
                              models: [AIModelEntry(name: "gpt")])
    imported.id = "provider-1"

    let restored = AppSettings.providersForImportedConfiguration([imported]) { providerID in
        providerID == "provider-1" ? "keychain-secret" : ""
    }
    expect(restored.first?.apiKey == "keychain-secret",
           "imported providers ignore plaintext file keys and use keychain resolver")

    let stripped = AppSettings.providersForImportedConfiguration([imported]) { _ in "" }
    expect(stripped.first?.apiKey == "",
           "imported providers strip plaintext keys when no local keychain value exists")
}

func testSettingsImportProvidersSanitizeRuntimeBoundaries() {
    var provider = AIProvider(name: String(repeating: "供应商", count: 80),
                              apiProtocol: .openAI,
                              baseURL: String(repeating: "https://example.test/", count: 40),
                              apiKey: "sk-plaintext-provider-key",
                              models: [
                                AIModelEntry(name: " gpt-4o-mini "),
                                AIModelEntry(name: "gpt-4o-mini"),
                                AIModelEntry(name: " "),
                                AIModelEntry(name: String(repeating: "m", count: AppSettings.importedModelNameLimit + 20))
                              ])
    provider.id = "provider-1"
    provider.temperature = 2.5
    provider.maxTokens = AppSettings.importedMaxTokensRange.upperBound + 100
    provider.requestTimeout = AppSettings.importedRequestTimeoutRange.upperBound + 30

    var duplicateProvider = provider
    duplicateProvider.name = "Duplicate"
    duplicateProvider.temperature = .infinity
    duplicateProvider.maxTokens = -10
    duplicateProvider.requestTimeout = -1

    let extras = (0..<(AppSettings.importedProviderLimit + 3)).map { index in
        AIProvider(name: "Extra \(index)",
                   apiProtocol: .openAI,
                   baseURL: "https://extra\(index).test/v1",
                   apiKey: "extra",
                   models: [AIModelEntry(name: "model-\(index)")])
    }

    let sanitized = AppSettings.providersForImportedConfiguration([provider, duplicateProvider] + extras) { providerID in
        providerID == "provider-1" ? "keychain-secret" : ""
    }

    expect(sanitized.count == AppSettings.importedProviderLimit,
           "import caps provider count")
    expect(Set(sanitized.map(\.id)).count == sanitized.count,
           "import assigns unique provider ids")
    expect(sanitized.first?.apiKey == "keychain-secret",
           "import keeps provider keys sourced from keychain")
    expect(sanitized.first?.name.count == AppSettings.importedProviderNameLimit,
           "import caps provider names")
    expect(sanitized.first?.baseURL.count == AppSettings.importedProviderBaseURLLimit,
           "import caps provider base URLs")
    expect(sanitized.first?.temperature == 1,
           "import clamps provider temperature overrides")
    expect(sanitized.first?.maxTokens == AppSettings.importedMaxTokensRange.upperBound,
           "import clamps provider max token overrides")
    expect(sanitized.first?.requestTimeout == AppSettings.importedRequestTimeoutRange.upperBound,
           "import clamps provider timeout overrides")
    expect(sanitized.first?.models.count == 2,
           "import drops blank and duplicate models")
    expect(sanitized.first?.models.first?.name == "gpt-4o-mini",
           "import trims model names")
    expect(sanitized.first?.models.last?.name.count == AppSettings.importedModelNameLimit,
           "import caps model names")
    expect(sanitized.dropFirst().first?.temperature == nil,
           "import drops non-finite provider temperature overrides")
    expect(sanitized.dropFirst().first?.maxTokens == nil,
           "import drops invalid provider max token overrides")
    expect(sanitized.dropFirst().first?.requestTimeout == nil,
           "import drops invalid provider timeout overrides")

    var activeDuplicateProvider = provider
    activeDuplicateProvider.name = "Active Duplicate"
    activeDuplicateProvider.models = [AIModelEntry(name: "duplicate-active-model")]
    let activeConfig = AppSettings.importedProviderConfiguration(
        [provider, activeDuplicateProvider],
        activeProviderID: "provider-1",
        activeModel: " duplicate-active-model "
    ) { providerID in
        providerID == "provider-1" ? "keychain-secret" : ""
    }
    expect(activeConfig.providers.count == 2,
           "import active provider mapping keeps both duplicate-id providers after id repair")
    expect(activeConfig.activeProviderID == activeConfig.providers[1].id,
           "import active provider mapping follows the duplicate provider that contains the active model")
    expect(activeConfig.activeProviderID != "provider-1",
           "import active provider mapping uses the repaired duplicate provider id")
    expect(activeConfig.activeModel == "duplicate-active-model",
           "import active provider mapping trims active model names")
}

func testSettingsImportRemapsActionProviderOverridesAfterProviderIDRepair() {
    let settings = AppSettings()
    var firstProvider = AIProvider(name: "First", apiProtocol: .openAI,
                                   baseURL: "https://first.test/v1",
                                   models: [AIModelEntry(name: "first-model")])
    firstProvider.id = "action-duplicate-provider"
    var secondProvider = AIProvider(name: "Second", apiProtocol: .openAI,
                                    baseURL: "https://second.test/v1",
                                    models: [AIModelEntry(name: "second-model")])
    secondProvider.id = "action-duplicate-provider"
    var action = AIAction(name: "专属动作",
                          prompt: "{{text}}")
    action.providerID = " action-duplicate-provider "
    action.modelOverride = " second-model "
    var invalidModelAction = AIAction(name: "无效专属模型",
                                      prompt: "{{text}}")
    invalidModelAction.providerID = "action-duplicate-provider"
    invalidModelAction.modelOverride = "missing-model"

    settings.providers = [firstProvider, secondProvider]
    settings.activeProviderID = "action-duplicate-provider"
    settings.activeModel = "first-model"
    settings.actions = [action, invalidModelAction]

    settings.normalizeImportedConfiguration()

    expect(settings.providers.count == 2,
           "import keeps duplicate provider entries after repairing ids")
    expect(settings.actions.first?.providerID == settings.providers[1].id,
           "import remaps action provider override to the repaired provider containing its model override")
    expect(settings.actions.first?.modelOverride == "second-model",
           "import trims action model overrides before provider mapping")
    expect(settings.actions.first?.providerID != "action-duplicate-provider",
           "import action provider override uses the repaired duplicate provider id")
    expect(settings.actions.dropFirst().first?.providerID == settings.providers.first?.id,
           "import keeps provider override when model override is invalid")
    expect(settings.actions.dropFirst().first?.modelOverride == nil,
           "import clears invalid action model overrides after provider mapping")
}

func testSettingsDecodeSanitizesStoredProviders() {
    let settings = AppSettings()
    var provider = AIProvider(name: String(repeating: "Provider", count: 40),
                              apiProtocol: .openAI,
                              baseURL: "  " + String(repeating: "https://stored.example/", count: 40) + "  ",
                              apiKey: "runtime-key",
                              models: [
                                AIModelEntry(name: " gpt-4o-mini "),
                                AIModelEntry(name: "gpt-4o-mini"),
                                AIModelEntry(name: " "),
                                AIModelEntry(name: String(repeating: "m", count: AppSettings.importedModelNameLimit + 20))
                              ])
    provider.id = "stored-provider"
    provider.temperature = 2.5
    provider.maxTokens = -10
    provider.requestTimeout = -1

    var duplicateProvider = provider
    duplicateProvider.name = "Duplicate"
    duplicateProvider.models = [AIModelEntry(name: "duplicate-model")]

    let extras = (0..<(AppSettings.importedProviderLimit + 3)).map { index in
        AIProvider(name: "Stored Extra \(index)",
                   apiProtocol: .openAI,
                   baseURL: "https://stored-extra\(index).test/v1",
                   models: [AIModelEntry(name: "stored-extra-model-\(index)")])
    }

    settings.providers = [provider, duplicateProvider] + extras
    settings.activeProviderID = provider.id
    settings.activeModel = "gpt-4o-mini"

    guard let data = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "settings stored provider decode succeeds")
        return
    }

    expect(decoded.providers.count == AppSettings.importedProviderLimit,
           "settings decode caps stored provider count")
    expect(decoded.providers.first?.id == "stored-provider",
           "settings decode preserves the first valid stored provider id for keychain lookup")
    expect(Set(decoded.providers.map(\.id)).count == decoded.providers.count,
           "settings decode assigns unique ids to duplicate stored providers")
    expect(decoded.providers.first?.name.count == AppSettings.importedProviderNameLimit,
           "settings decode caps stored provider names")
    expect(decoded.providers.first?.baseURL.count == AppSettings.importedProviderBaseURLLimit,
           "settings decode caps stored provider base URLs")
    expect(decoded.providers.first?.temperature == 1,
           "settings decode clamps stored provider temperature overrides")
    expect(decoded.providers.first?.maxTokens == nil,
           "settings decode drops invalid stored provider max token overrides")
    expect(decoded.providers.first?.requestTimeout == nil,
           "settings decode drops invalid stored provider timeout overrides")
    expect(decoded.providers.first?.models.count == 2,
           "settings decode drops blank and duplicate stored models")
    expect(decoded.providers.first?.models.first?.name == "gpt-4o-mini",
           "settings decode trims stored model names")
    expect(decoded.providers.first?.models.last?.name.count == AppSettings.importedModelNameLimit,
           "settings decode caps stored model names")
    expect(decoded.activeProviderID == "stored-provider",
           "settings decode keeps active provider when it remains valid")
    expect(decoded.activeModel == "gpt-4o-mini",
           "settings decode keeps active model after model sanitization")

    let activeDuplicateSettings = AppSettings()
    var firstDuplicate = AIProvider(name: "First", apiProtocol: .openAI,
                                    baseURL: "https://first.test/v1",
                                    models: [AIModelEntry(name: "first-model")])
    firstDuplicate.id = "duplicate-active-provider"
    var secondDuplicate = AIProvider(name: "Second", apiProtocol: .openAI,
                                     baseURL: "https://second.test/v1",
                                     models: [AIModelEntry(name: "second-model")])
    secondDuplicate.id = "duplicate-active-provider"
    activeDuplicateSettings.providers = [firstDuplicate, secondDuplicate]
    activeDuplicateSettings.activeProviderID = "duplicate-active-provider"
    activeDuplicateSettings.activeModel = " second-model "
    var duplicateAction = AIAction(name: "Stored Override", prompt: "{{text}}")
    duplicateAction.providerID = "duplicate-active-provider"
    duplicateAction.modelOverride = "second-model"
    activeDuplicateSettings.actions = [duplicateAction]

    guard let duplicateData = try? JSONEncoder().encode(activeDuplicateSettings),
          let duplicateDecoded = try? JSONDecoder().decode(AppSettings.self, from: duplicateData) else {
        expect(false, "settings decode succeeds for duplicate active provider fixture")
        return
    }
    expect(duplicateDecoded.providers.count == 2,
           "settings decode keeps duplicate-id providers after repairing ids")
    expect(duplicateDecoded.activeProviderID == duplicateDecoded.providers[1].id,
           "settings decode remaps active provider to the repaired duplicate id when its model matches")
    expect(duplicateDecoded.activeProviderID != "duplicate-active-provider",
           "settings decode active provider uses the repaired duplicate id")
    expect(duplicateDecoded.activeModel == "second-model",
           "settings decode trims active model names before normalization")
    expect(duplicateDecoded.actions.first?.providerID == duplicateDecoded.providers[1].id,
           "settings decode remaps action provider overrides to repaired duplicate provider ids")
    expect(duplicateDecoded.actions.first?.modelOverride == "second-model",
           "settings decode preserves action model overrides after provider id repair")
}

func testSettingsImportSanitizesUnsafeConfiguration() {
    let settings = AppSettings()
    settings.temperature = 2.5
    settings.historyLimit = 50_000
    settings.askPrompt = " \n"
    settings.translatePrompt = String(repeating: "t", count: AppSettings.importedPromptLimit + 25)
    settings.systemPrompt = "\n\t"

    var firstRule = PrivacyRedactionRule(
        name: String(repeating: "规则", count: 80),
        pattern: #"\d+"#,
        replacement: String(repeating: "x", count: AppSettings.importedRedactionReplacementLimit + 20)
    )
    firstRule.id = "duplicate-rule"
    var secondRule = PrivacyRedactionRule(
        name: "字母",
        pattern: #"[A-Z]+"#,
        replacement: "[字母]"
    )
    secondRule.id = "duplicate-rule"
    let invalidRule = PrivacyRedactionRule(name: "坏规则", pattern: "(", replacement: "[坏]")
    let overlongRule = PrivacyRedactionRule(
        name: "过长规则",
        pattern: String(repeating: "a", count: AppSettings.importedRedactionPatternLimit + 1),
        replacement: "[长]"
    )
    settings.redactionRules = [firstRule, secondRule, invalidRule, overlongRule]

    let longContent = String(repeating: "上下文", count: AppSettings.importedContextContentLimit)
    var activeProfile = ContextProfile(
        name: String(repeating: "项目", count: 80),
        content: longContent,
        isEnabled: true
    )
    activeProfile.id = "duplicate-context"
    var duplicateProfile = ContextProfile(name: "备用", content: "备用内容", isEnabled: true)
    duplicateProfile.id = "duplicate-context"
    let blankProfile = ContextProfile(name: "  ", content: "\n", isEnabled: true)
    settings.contextProfiles = [activeProfile, duplicateProfile, blankProfile]
    settings.activeContextProfileID = activeProfile.id

    settings.normalizeImportedConfiguration()

    expect(settings.temperature == 1, "import clamps high temperature to supported range")
    expect(settings.historyLimit == 500, "import clamps history limit to UI-supported range")
    expect(settings.askPrompt == AppSettings.defaultAskPrompt,
           "import replaces blank ask prompts with the default prompt")
    expect(settings.translatePrompt.count == AppSettings.importedPromptLimit,
           "import caps overlong translate prompts")
    expect(settings.systemPrompt == "",
           "import preserves intentionally blank system prompts")
    expect(settings.redactionRules.count == 2, "import drops invalid and overlong redaction rules")
    expect(Set(settings.redactionRules.map(\.id)).count == settings.redactionRules.count,
           "import assigns unique redaction rule ids")
    expect(settings.redactionRules.first?.name.count == AppSettings.importedRedactionNameLimit,
           "import caps redaction rule names")
    expect(settings.redactionRules.first?.replacement.count == AppSettings.importedRedactionReplacementLimit,
           "import caps redaction replacements")
    expect(AppSettings.sanitizedImportedRedactionRules([]).isEmpty,
           "import preserves an explicitly empty redaction rule list")
    let importedLegacyDefaults = AppSettings.sanitizedImportedRedactionRules(legacyDefaultRedactionRulesForTests())
    expect(importedLegacyDefaults.map(\.name) == PrivacyRedactionRule.defaults().map(\.name),
           "import migrates exact legacy default redaction rules to current defaults")
    expect(importedLegacyDefaults.contains { $0.name == "私钥与 JWT" },
           "import adds current private-key and JWT redaction rule for legacy defaults")
    var customizedImportedLegacyRules = legacyDefaultRedactionRulesForTests()
    customizedImportedLegacyRules[2].name = "我的密钥规则"
    let importedCustomRules = AppSettings.sanitizedImportedRedactionRules(customizedImportedLegacyRules)
    expect(importedCustomRules.map(\.name).contains("我的密钥规则"),
           "import preserves customized legacy-looking redaction rule sets")
    expect(!importedCustomRules.contains { $0.name == "私钥与 JWT" },
           "import avoids injecting current defaults into customized redaction rule sets")
    expect(settings.contextProfiles.count == 2, "import drops blank context profiles")
    expect(Set(settings.contextProfiles.map(\.id)).count == settings.contextProfiles.count,
           "import assigns unique context profile ids")
    expect(settings.contextProfiles.first?.name.count == AppSettings.importedContextNameLimit,
           "import caps context profile names")
    expect(settings.contextProfiles.first?.content.count == AppSettings.importedContextContentLimit,
           "import caps context profile content")
    expect(settings.activeContextProfileID == settings.contextProfiles.first?.id,
           "import preserves the active context when it remains usable")
}

func testSettingsDecodeSanitizesStoredContextProfiles() {
    let settings = AppSettings()
    var activeProfile = ContextProfile(
        name: String(repeating: "项目", count: AppSettings.importedContextNameLimit),
        content: String(repeating: "上下文", count: AppSettings.importedContextContentLimit),
        isEnabled: true
    )
    activeProfile.id = "stored-context"
    var duplicateProfile = ContextProfile(name: "备用", content: "备用内容", isEnabled: true)
    duplicateProfile.id = "stored-context"
    let blankProfile = ContextProfile(name: "  ", content: "\n", isEnabled: true)
    settings.contextProfiles = [activeProfile, duplicateProfile, blankProfile]
    settings.activeContextProfileID = activeProfile.id

    guard let data = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "settings stored context decode succeeds")
        return
    }

    expect(decoded.contextProfiles.count == 2,
           "settings decode drops blank stored context profiles")
    expect(decoded.contextProfiles.first?.id == "stored-context",
           "settings decode preserves first valid stored context profile id")
    expect(Set(decoded.contextProfiles.map(\.id)).count == decoded.contextProfiles.count,
           "settings decode assigns unique ids to duplicate stored context profiles")
    expect(decoded.contextProfiles.first?.name.count == AppSettings.importedContextNameLimit,
           "settings decode caps stored context profile names")
    expect(decoded.contextProfiles.first?.content.count == AppSettings.importedContextContentLimit,
           "settings decode caps stored context profile content")
    expect(decoded.activeContextProfileID == decoded.contextProfiles.first?.id,
           "settings decode keeps active stored context when it remains usable")
    expect(decoded.activeContextProfile?.content.count == AppSettings.importedContextContentLimit,
           "settings decode active context uses sanitized content")
}

func testSettingsDecodeSanitizesStoredPrompts() {
    let settings = AppSettings()
    settings.askPrompt = String(repeating: "a", count: AppSettings.importedPromptLimit + 25)
    settings.translatePrompt = AppSettings.oldDefaultTranslatePrompt
    settings.systemPrompt = String(repeating: "s", count: AppSettings.importedSystemPromptLimit + 25)

    guard let data = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "settings stored prompt decode succeeds")
        return
    }

    expect(decoded.askPrompt.count == AppSettings.importedPromptLimit,
           "settings decode caps stored ask prompts")
    expect(decoded.translatePrompt == AppSettings.defaultTranslatePrompt,
           "settings decode migrates the old default translate prompt")
    expect(decoded.systemPrompt.count == AppSettings.importedSystemPromptLimit,
           "settings decode caps stored system prompts")

    let blankSettings = AppSettings()
    blankSettings.askPrompt = " \n"
    blankSettings.translatePrompt = "\t"
    blankSettings.systemPrompt = "\n "

    guard let blankData = try? JSONEncoder().encode(blankSettings),
          let blankDecoded = try? JSONDecoder().decode(AppSettings.self, from: blankData) else {
        expect(false, "settings blank prompt decode succeeds")
        return
    }

    expect(blankDecoded.askPrompt == AppSettings.defaultAskPrompt,
           "settings decode replaces blank ask prompts with the default prompt")
    expect(blankDecoded.translatePrompt == AppSettings.defaultTranslatePrompt,
           "settings decode replaces blank translate prompts with the default prompt")
    expect(blankDecoded.systemPrompt == "",
           "settings decode preserves intentionally blank system prompts")
}

func testSettingsDecodeDefaultsRoutingPreference() {
    let json = #"{"settingsSchemaVersion":2,"providers":[]}"#.data(using: .utf8)!
    guard let decoded = try? JSONDecoder().decode(AppSettings.self, from: json) else {
        expect(false, "settings decode succeeds with sparse JSON")
        return
    }
    expect(decoded.routingPreference == .balanced, "defaults missing routing preference to balanced")
    expect(decoded.historyContentStorage == .full, "defaults missing history content storage to full")
}

func testSettingsDecodeDefaultsActiveProviderToFirstProvider() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Provider", apiProtocol: .openAI,
                              baseURL: "https://example.test/v1",
                              apiKey: "secret",
                              models: [AIModelEntry(name: "gpt-4o-mini")])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "gpt-4o-mini"

    guard let data = try? JSONEncoder().encode(settings),
          var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        expect(false, "settings encode succeeds for active provider fallback fixture")
        return
    }
    object.removeValue(forKey: "activeProviderID")
    guard let stripped = try? JSONSerialization.data(withJSONObject: object),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: stripped) else {
        expect(false, "settings decode succeeds without activeProviderID")
        return
    }
    expect(decoded.activeProviderID == provider.id, "defaults missing active provider id to first provider")
}

func testSettingsNormalizeActiveSkipsDisabledProviderAndModel() {
    let settings = AppSettings()
    var disabledProvider = AIProvider(name: "Disabled", apiProtocol: .openAI,
                                      baseURL: "https://disabled.test/v1",
                                      apiKey: "key",
                                      models: [AIModelEntry(name: "disabled-provider-model")])
    disabledProvider.isEnabled = false
    var enabledProvider = AIProvider(name: "Enabled", apiProtocol: .openAI,
                                     baseURL: "https://enabled.test/v1",
                                     apiKey: "key",
                                     models: [
                                        AIModelEntry(name: "disabled-model", enabled: false),
                                        AIModelEntry(name: "enabled-model", enabled: true)
                                     ])
    enabledProvider.isEnabled = true
    settings.providers = [disabledProvider, enabledProvider]
    settings.activeProviderID = disabledProvider.id
    settings.activeModel = "disabled-model"

    settings.normalizeActive()

    expect(settings.activeProviderID == enabledProvider.id, "normalizes disabled active provider to first enabled provider")
    expect(settings.activeModel == "enabled-model", "normalizes disabled active model to first enabled model")
}

func testSettingsNormalizeActiveClearsWhenNoEnabledProviderExists() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Disabled", apiProtocol: .openAI,
                              baseURL: "https://disabled.test/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "model")])
    provider.isEnabled = false
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "model"

    settings.normalizeActive()

    expect(settings.activeProviderID.isEmpty, "clears active provider when no provider is enabled")
    expect(settings.activeModel.isEmpty, "clears active model when no provider is enabled")
}

func testCloudSettingsPayloadPreservesRoutingPreferenceAndNormalizesModel() {
    let source = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "sk-cloud-secret-abcdefghijklmnopqrstuvwxyz",
                              models: [
                                AIModelEntry(name: "disabled-active", enabled: false),
                                AIModelEntry(name: "enabled-model", enabled: true)
                              ])
    provider.isEnabled = true
    source.providers = [provider]
    source.activeProviderID = provider.id
    source.activeModel = "disabled-active"
    source.routingPreference = .quality
    source.historyContentStorage = .metadataOnly
    source.temperature = 3.5
    source.askPrompt = String(repeating: "a", count: AppSettings.importedPromptLimit + 25)
    source.translatePrompt = AppSettings.oldDefaultTranslatePrompt
    source.systemPrompt = " \n"
    let validRule = PrivacyRedactionRule(name: "数字", pattern: #"\d+"#, replacement: "[数字]")
    let invalidRule = PrivacyRedactionRule(name: "坏规则", pattern: "(", replacement: "[坏]")
    source.redactionRules = [validRule, invalidRule]
    let longCloudContext = String(repeating: "云", count: AppSettings.importedContextContentLimit + 25)
    let cloudProfile = ContextProfile(name: "Cloud", content: longCloudContext, isEnabled: true)
    source.contextProfiles = [cloudProfile]
    source.activeContextProfileID = cloudProfile.id

    guard let data = try? JSONEncoder().encode(CloudSettingsPayload(settings: source)),
          let decoded = try? JSONDecoder().decode(CloudSettingsPayload.self, from: data),
          let json = String(data: data, encoding: .utf8) else {
        expect(false, "cloud settings payload encode/decode succeeds")
        return
    }

    let target = AppSettings()
    decoded.apply(to: target)

    expect(CloudSettingsPayload(settings: source).providers.first?.apiKey == "",
           "cloud payload strips provider api key before encoding")
    expect(!json.contains("\"apiKey\""), "cloud payload omits apiKey field")
    expect(!json.contains(provider.apiKey), "cloud payload omits provider api key value")
    expect(decoded.providers.first?.apiKey == "", "cloud payload decodes with empty api key")
    expect(target.providers.first?.apiKey == "", "cloud payload apply does not introduce payload api key")
    expect(target.routingPreference == .quality, "cloud payload preserves routing preference")
    expect(target.historyContentStorage == .metadataOnly, "cloud payload preserves history content storage preference")
    expect(target.activeModel == "enabled-model", "cloud payload normalizes disabled active model on apply")
    expect(target.temperature == 1, "cloud payload clamps imported temperature")
    expect(decoded.askPrompt.count == AppSettings.importedPromptLimit,
           "cloud payload caps ask prompts before syncing")
    expect(decoded.translatePrompt == AppSettings.defaultTranslatePrompt,
           "cloud payload migrates the old translate prompt")
    expect(decoded.systemPrompt == "",
           "cloud payload preserves intentionally blank system prompts")
    expect(target.askPrompt.count == AppSettings.importedPromptLimit,
           "cloud payload applies capped ask prompts")
    expect(target.translatePrompt == AppSettings.defaultTranslatePrompt,
           "cloud payload applies migrated translate prompts")
    expect(target.systemPrompt == "",
           "cloud payload applies blank system prompts")
    expect(target.redactionRules.count == 1 && target.redactionRules.first?.pattern == #"\d+"#,
           "cloud payload drops invalid redaction rules")
    expect(target.contextProfiles.first?.content.count == AppSettings.importedContextContentLimit,
           "cloud payload caps context profile content")
    expect(target.activeContextProfileID == target.contextProfiles.first?.id,
           "cloud payload preserves usable active context after sanitizing")
}

func testCloudSettingsPayloadRemapsActiveProviderAfterProviderIDRepair() {
    let source = AppSettings()
    var firstProvider = AIProvider(name: "First", apiProtocol: .openAI,
                                   baseURL: "https://first.test/v1",
                                   apiKey: "first-secret",
                                   models: [AIModelEntry(name: "first-model")])
    firstProvider.id = "cloud-duplicate-provider"
    var secondProvider = AIProvider(name: "Second", apiProtocol: .openAI,
                                    baseURL: "https://second.test/v1",
                                    apiKey: "second-secret",
                                    models: [AIModelEntry(name: "second-model")])
    secondProvider.id = "cloud-duplicate-provider"
    source.providers = [firstProvider, secondProvider]
    source.activeProviderID = "cloud-duplicate-provider"
    source.activeModel = " second-model "
    var action = AIAction(name: "Cloud Override", prompt: "{{text}}")
    action.providerID = "cloud-duplicate-provider"
    action.modelOverride = " second-model "
    var invalidModelAction = AIAction(name: "Cloud Invalid Override", prompt: "{{text}}")
    invalidModelAction.providerID = "cloud-duplicate-provider"
    invalidModelAction.modelOverride = "missing-model"
    source.actions = [action, invalidModelAction]

    guard let data = try? JSONEncoder().encode(CloudSettingsPayload(settings: source)),
          let payload = try? JSONDecoder().decode(CloudSettingsPayload.self, from: data) else {
        expect(false, "cloud duplicate provider payload encode/decode succeeds")
        return
    }

    let target = AppSettings()
    payload.apply(to: target)

    expect(target.providers.count == 2,
           "cloud payload keeps duplicate-id providers after repairing ids")
    expect(Set(target.providers.map(\.id)).count == target.providers.count,
           "cloud payload repairs duplicate provider ids")
    expect(target.activeProviderID == target.providers[1].id,
           "cloud payload remaps active provider to the repaired duplicate id when its model matches")
    expect(target.activeProviderID != "cloud-duplicate-provider",
           "cloud payload active provider uses the repaired duplicate id")
    expect(target.activeModel == "second-model",
           "cloud payload trims active model names before normalization")
    expect(target.model == "second-model",
           "cloud payload keeps the active model available after provider id repair")
    expect(target.actions.first?.providerID == target.providers[1].id,
           "cloud payload remaps action provider override to the repaired duplicate provider id")
    expect(target.actions.first?.modelOverride == "second-model",
           "cloud payload trims action model overrides before provider mapping")
    expect(target.actions.dropFirst().first?.providerID == target.providers.first?.id,
           "cloud payload keeps provider override when model override is invalid")
    expect(target.actions.dropFirst().first?.modelOverride == nil,
           "cloud payload clears invalid action model overrides after provider mapping")
}

func testCloudSettingsPayloadDecodeRemapsActionsAfterProviderIDRepair() {
    let json = #"""
    {
      "providers": [
        {
          "id": "cloud-duplicate-provider",
          "name": "First",
          "apiProtocol": "OpenAI 兼容",
          "baseURL": "https://first.test/v1",
          "models": [
            { "name": "first-model", "enabled": true }
          ],
          "isEnabled": true
        },
        {
          "id": "cloud-duplicate-provider",
          "name": "Second",
          "apiProtocol": "OpenAI 兼容",
          "baseURL": "https://second.test/v1",
          "models": [
            { "name": "second-model", "enabled": true }
          ],
          "isEnabled": true
        }
      ],
      "activeProviderID": "cloud-duplicate-provider",
      "activeModel": " second-model ",
      "actions": [
        {
          "id": "cloud-action",
          "name": "Cloud Override",
          "prompt": "{{text}}",
          "providerID": " cloud-duplicate-provider ",
          "modelOverride": " second-model "
        }
      ]
    }
    """#
    guard let data = json.data(using: .utf8),
          let payload = try? JSONDecoder().decode(CloudSettingsPayload.self, from: data) else {
        expect(false, "cloud payload decodes raw duplicate provider json")
        return
    }

    expect(payload.providers.count == 2,
           "cloud payload decode keeps duplicate-id providers after repairing ids")
    expect(Set(payload.providers.map(\.id)).count == payload.providers.count,
           "cloud payload decode repairs duplicate provider ids")
    expect(payload.activeProviderID == payload.providers[1].id,
           "cloud payload decode remaps active provider to the repaired duplicate id")
    expect(payload.activeModel == "second-model",
           "cloud payload decode trims active model names")
    expect(payload.actions.first?.providerID == payload.providers[1].id,
           "cloud payload decode remaps action provider override to the repaired duplicate id")
    expect(payload.actions.first?.modelOverride == "second-model",
           "cloud payload decode trims action model override before mapping")
}

func testWorkModePresetsApplyCoherentSettings() {
    let settings = AppSettings()

    settings.applyWorkMode(.privacy)
    expect(settings.workModePreset == .privacy, "privacy mode is recorded as the last applied preset")
    expect(settings.privacyPreviewEnabled, "privacy mode enables submission preview")
    expect(settings.redactionEnabled, "privacy mode enables local redaction")
    expect(settings.historyContentStorage == .metadataOnly, "privacy mode stores history metadata only")
    expect(settings.autoRouteEnabled, "privacy mode keeps automatic routing available")
    expect(settings.fallbackEnabled, "privacy mode keeps fallback enabled")
    expect(settings.routingPreference == .balanced, "privacy mode keeps balanced routing")
    expect(settings.matchingWorkModePreset == .privacy, "privacy mode can be inferred from current behavior")
    expect(settings.workModeStatusTitle == "隐私模式", "work mode status names the matched preset")

    settings.redactionEnabled = false
    expect(settings.matchingWorkModePreset == nil, "manual changes can make the current behavior custom")
    expect(settings.workModeStatusTitle == "自定义模式", "work mode status reports custom behavior")
    expect(settings.workModeStatusDetail.contains("偏离预设"), "custom work mode explains the mismatch")

    settings.applyWorkMode(.speed)
    expect(settings.matchingWorkModePreset == .speed, "speed mode can be inferred from current behavior")
    expect(settings.routingPreference == .fastest, "speed mode selects fastest routing")
    expect(settings.historyContentStorage == .full, "speed mode keeps full history")
    expect(!settings.privacyPreviewEnabled, "speed mode avoids extra preview confirmation")
    expect(!settings.redactionEnabled, "speed mode avoids redaction overhead")

    settings.applyWorkMode(.quality)
    expect(settings.matchingWorkModePreset == .quality, "quality mode can be inferred from current behavior")
    expect(settings.autoRouteEnabled, "quality mode enables automatic routing")
    expect(settings.routingPreference == .quality, "quality mode selects quality routing")

    guard let encoded = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: encoded) else {
        expect(false, "work mode settings round-trip through AppSettings codable")
        return
    }
    expect(decoded.workModePreset == .quality, "AppSettings codable preserves last applied work mode")
    expect(decoded.matchingWorkModePreset == .quality, "AppSettings codable preserves coherent work mode behavior")

    let payload = CloudSettingsPayload(settings: settings)
    guard let payloadData = try? JSONEncoder().encode(payload),
          let decodedPayload = try? JSONDecoder().decode(CloudSettingsPayload.self, from: payloadData) else {
        expect(false, "work mode settings round-trip through iCloud payload")
        return
    }
    let synced = AppSettings()
    decodedPayload.apply(to: synced)
    expect(synced.workModePreset == .quality, "iCloud payload preserves last applied work mode")
    expect(synced.matchingWorkModePreset == .quality, "iCloud payload applies coherent work mode behavior")
}

func testAppSettingsUpsertsHistoryContextProfileByName() {
    let settings = AppSettings()
    settings.contextProfiles = []
    settings.activeContextProfileID = ""

    let firstDraft = HistoryContextProfileDraft(name: " 历史上下文 - 项目A ",
                                                content: "旧上下文",
                                                includedCount: 1,
                                                skippedCount: 0)
    let first = settings.upsertContextProfile(from: firstDraft)

    expect(!first.didUpdate, "first history context upsert creates a new profile")
    expect(settings.contextProfiles.count == 1, "history context upsert appends when no matching profile exists")
    expect(settings.contextProfiles[0].name == "历史上下文 - 项目A", "history context upsert trims generated names")
    expect(settings.contextProfiles[0].content == "旧上下文", "history context upsert stores draft content")
    expect(settings.contextProfiles[0].isEnabled, "history context upsert creates enabled profiles")
    expect(settings.activeContextProfileID == first.profile.id, "history context upsert activates created profile")
    expect(settings.hasContextProfile(named: "历史上下文 - 项目A"), "history context lookup finds trimmed names")

    let originalID = first.profile.id
    settings.contextProfiles[0].isEnabled = false
    settings.activeContextProfileID = "other"

    let secondDraft = HistoryContextProfileDraft(name: "历史上下文 - 项目A",
                                                 content: "新上下文",
                                                 includedCount: 2,
                                                 skippedCount: 1)
    let second = settings.upsertContextProfile(from: secondDraft)

    expect(second.didUpdate, "second history context upsert updates matching profile")
    expect(settings.contextProfiles.count == 1, "history context upsert avoids duplicate generated profiles")
    expect(settings.contextProfiles[0].id == originalID, "history context upsert preserves existing profile id")
    expect(settings.contextProfiles[0].content == "新上下文", "history context upsert refreshes existing content")
    expect(settings.contextProfiles[0].isEnabled, "history context upsert re-enables existing profile")
    expect(settings.activeContextProfileID == originalID, "history context upsert activates updated profile")
    expect(second.profile.id == originalID, "history context upsert result returns updated profile")

    let generatedSettings = AppSettings()
    generatedSettings.contextProfiles = []
    let entry = HistoryEntry(actionName: "总结",
                             source: "原文",
                             output: "第一次",
                             provider: "OpenAI",
                             model: "gpt")
    let updatedEntry = HistoryEntry(actionName: "总结",
                                    source: "原文",
                                    output: "第二次",
                                    provider: "OpenAI",
                                    model: "gpt")
    guard let generatedFirst = HistoryContextProfileBuilder.draft(entries: [entry],
                                                                  criteria: HistoryFilterCriteria(),
                                                                  date: Date(timeIntervalSince1970: 0)),
          let generatedSecond = HistoryContextProfileBuilder.draft(entries: [updatedEntry],
                                                                   criteria: HistoryFilterCriteria(),
                                                                   date: Date(timeIntervalSince1970: 3_600)) else {
        expect(false, "creates generated all-history context drafts")
        return
    }
    let generatedResult = generatedSettings.upsertContextProfile(from: generatedFirst)
    let generatedUpdate = generatedSettings.upsertContextProfile(from: generatedSecond)
    expect(generatedResult.profile.name == "历史上下文 - 全部历史",
           "generated all-history context upsert uses stable profile name")
    expect(generatedUpdate.didUpdate, "repeated all-history context upsert updates existing profile")
    expect(generatedSettings.contextProfiles.count == 1,
           "repeated all-history context upsert avoids duplicate timestamped profiles")
    expect(generatedSettings.contextProfiles[0].content.contains("第二次"),
           "repeated all-history context upsert refreshes generated content")

    var namedDraft = generatedFirst
    namedDraft.name = "项目A上下文"
    var namedUpdateDraft = generatedSecond
    namedUpdateDraft.name = " 项目A上下文 "
    let namedSettings = AppSettings()
    namedSettings.contextProfiles = []
    let namedCreate = namedSettings.upsertContextProfile(from: namedDraft)
    let namedUpdate = namedSettings.upsertContextProfile(from: namedUpdateDraft)
    expect(namedCreate.profile.name == "项目A上下文", "custom history context names are preserved")
    expect(namedUpdate.didUpdate, "custom named history context upsert updates matching profile")
    expect(namedSettings.contextProfiles.count == 1, "custom named history context avoids duplicate profiles")
    expect(namedSettings.contextProfiles[0].id == namedCreate.profile.id,
           "custom named history context upsert preserves profile identity")
}
