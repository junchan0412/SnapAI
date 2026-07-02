import Foundation
import Carbon.HIToolbox
import Combine

/// AI 协议类型
enum APIProtocol: String, Codable, CaseIterable, Identifiable {
    case openAI = "OpenAI 兼容"
    case anthropic = "Anthropic 原生"
    var id: String { rawValue }
}

/// 打字机动画速度
enum TypewriterSpeed: String, Codable, CaseIterable, Identifiable {
    case off = "关闭"
    case slow = "慢"
    case normal = "标准"
    case fast = "快"
    var id: String { rawValue }

    /// 每次 tick 揭示的字符数
    var charsPerTick: Int {
        switch self {
        case .off: return 0       // 0 表示不走打字机,直接整段显示
        case .slow: return 1
        case .normal: return 2
        case .fast: return 5
        }
    }

    /// tick 间隔(秒)
    var tickInterval: TimeInterval {
        switch self {
        case .off: return 0
        case .slow: return 0.03
        case .normal: return 0.012
        case .fast: return 0.008
        }
    }
}

/// AI 自动路由偏好。
enum AIRoutingPreference: String, Codable, CaseIterable, Identifiable {
    case fastest = "最快"
    case balanced = "均衡"
    case quality = "最佳质量"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .fastest:
            return "优先低延迟和低成本模型"
        case .balanced:
            return "兼顾速度、成本和任务适配"
        case .quality:
            return "优先长上下文、推理和复杂任务能力"
        }
    }
}

/// 历史记录内容保存策略。
enum HistoryContentStorage: String, Codable, CaseIterable, Identifiable {
    case full = "完整保存"
    case metadataOnly = "仅元信息"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .full:
            return "保存原文和结果,便于搜索与回看"
        case .metadataOnly:
            return "只保存动作、模型、时间和隐私标签"
        }
    }
}

struct WorkModeBehavior: Equatable {
    var privacyPreviewEnabled: Bool
    var redactionEnabled: Bool
    var historyContentStorage: HistoryContentStorage
    var autoRouteEnabled: Bool
    var fallbackEnabled: Bool
    var routingPreference: AIRoutingPreference
}

enum WorkModePreset: String, Codable, CaseIterable, Identifiable {
    case standard
    case privacy
    case speed
    case quality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "标准模式"
        case .privacy: return "隐私模式"
        case .speed: return "极速模式"
        case .quality: return "质量模式"
        }
    }

    var shortTitle: String {
        switch self {
        case .standard: return "标准"
        case .privacy: return "隐私"
        case .speed: return "极速"
        case .quality: return "质量"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: return "slider.horizontal.3"
        case .privacy: return "hand.raised"
        case .speed: return "bolt"
        case .quality: return "sparkles"
        }
    }

    var summary: String {
        switch self {
        case .standard:
            return "平衡日常效率与完整历史记录。"
        case .privacy:
            return "发送前确认、本地脱敏,历史仅保存元信息。"
        case .speed:
            return "自动路由到低延迟模型,减少确认步骤。"
        case .quality:
            return "自动路由并优先质量,适合长文和复杂任务。"
        }
    }

    var keywords: String {
        switch self {
        case .standard:
            return "work mode standard default balanced settings 模式 标准 默认 均衡"
        case .privacy:
            return "work mode privacy preview redaction metadata history safe 隐私 预览 脱敏 元信息"
        case .speed:
            return "work mode speed fastest route low latency quick 极速 快速 路由 低延迟"
        case .quality:
            return "work mode quality best route reasoning long context 质量 最佳 长文 推理"
        }
    }

    var behavior: WorkModeBehavior {
        switch self {
        case .standard:
            return WorkModeBehavior(privacyPreviewEnabled: false,
                                    redactionEnabled: false,
                                    historyContentStorage: .full,
                                    autoRouteEnabled: false,
                                    fallbackEnabled: true,
                                    routingPreference: .balanced)
        case .privacy:
            return WorkModeBehavior(privacyPreviewEnabled: true,
                                    redactionEnabled: true,
                                    historyContentStorage: .metadataOnly,
                                    autoRouteEnabled: true,
                                    fallbackEnabled: true,
                                    routingPreference: .balanced)
        case .speed:
            return WorkModeBehavior(privacyPreviewEnabled: false,
                                    redactionEnabled: false,
                                    historyContentStorage: .full,
                                    autoRouteEnabled: true,
                                    fallbackEnabled: true,
                                    routingPreference: .fastest)
        case .quality:
            return WorkModeBehavior(privacyPreviewEnabled: false,
                                    redactionEnabled: false,
                                    historyContentStorage: .full,
                                    autoRouteEnabled: true,
                                    fallbackEnabled: true,
                                    routingPreference: .quality)
        }
    }
}

struct ContextStatusSummary: Equatable {
    var profileCount: Int
    var usableProfileCount: Int
    var activeProfileName: String
    var activeContextCharacterCount: Int
    var globalSystemPromptCharacterCount: Int
    var effectiveSystemPromptCharacterCount: Int

    var hasActiveContext: Bool {
        activeContextCharacterCount > 0
    }

    var activeProfileDisplayName: String {
        activeProfileName.isEmpty ? "无" : activeProfileName
    }

    var shareableActiveContextState: String {
        hasActiveContext ? "set" : "none"
    }

    var shareableActiveProfileNameCharacterCount: Int {
        hasActiveContext ? activeProfileName.count : 0
    }

    static func make(settings: AppSettings) -> ContextStatusSummary {
        let usableProfiles = settings.contextProfiles.filter {
            $0.isEnabled && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let activeProfile = settings.activeContextProfile
        let activeName = activeProfile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let activeCharacters = activeProfile?.content.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
        return ContextStatusSummary(
            profileCount: settings.contextProfiles.count,
            usableProfileCount: usableProfiles.count,
            activeProfileName: activeName,
            activeContextCharacterCount: activeCharacters,
            globalSystemPromptCharacterCount: settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count,
            effectiveSystemPromptCharacterCount: settings.effectiveSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count
        )
    }
}

/// 一个可配置的快捷键(键码 + 修饰键)
struct HotKeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon 修饰键掩码 (cmdKey/optionKey/...)

    static let askDefault = HotKeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey))
    static let translateDefault = HotKeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey))

    /// 人类可读描述,如 "⌥A"
    var displayString: String {
        if modifiers == 0 { return "未设置" }
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += KeyCodeMap.name(for: keyCode)
        return s
    }
}

/// 全局设置,持久化到 UserDefaults
final class AppSettings: ObservableObject, Codable {
    static let shared = AppSettings.load()
    static let currentSchemaVersion = 2
    static let defaultPanelWidth: Double = 420
    static let defaultPanelHeight: Double = 360
    static let importedPanelWidthRange: ClosedRange<Double> = 320...1_400
    static let importedPanelHeightRange: ClosedRange<Double> = 200...1_000
    static let importedHistoryLimitRange = 0...500
    static let importedRedactionRuleLimit = 80
    static let importedRedactionNameLimit = 80
    static let importedRedactionPatternLimit = PrivacyFilter.maxPatternLength
    static let importedRedactionReplacementLimit = PrivacyFilter.maxReplacementLength
    static let importedContextProfileLimit = 24
    static let importedContextNameLimit = 80
    static let importedContextContentLimit = 40_000
    static let importedProviderLimit = 12
    static let importedProviderNameLimit = 80
    static let importedProviderBaseURLLimit = 500
    static let importedModelLimit = 200
    static let importedModelNameLimit = 160
    static let importedPromptLimit = AIAction.maxPromptLength
    static let importedSystemPromptLimit = AIAction.maxPromptLength
    static let importedMaxTokensRange = 1...200_000
    static let importedRequestTimeoutRange: ClosedRange<Double> = 5...300
    static let importedActionLimit = 80
    static let importedActionUsageLimit = 200
    static let importedActionUsageCountRange = 1...1_000_000
    static let historySourceCharacterLimit = 20_000
    static let historyOutputCharacterLimit = 40_000
    static let historyTagLimit = 24
    static let historyTagCharacterLimit = 48
    static let importedSavedHistoryFilterLimit = 24
    static let importedSavedHistoryFilterNameLimit = 80
    static let importedSavedHistoryFilterQueryLimit = 240
    static let defaultAskPrompt = "请简洁、准确地回答关于以下内容的问题或解释它:\n\n{{text}}"
    static let oldDefaultTranslatePrompt = "请把下面的文字翻译成中文;如果它本身就是中文,则翻译成英文。只输出翻译结果,不要解释:\n\n{{text}}"
    static let defaultTranslatePrompt = "请将下面的文字在中文和英文之间互译:如果原文是中文,翻译成自然流畅的英文;如果原文是英文或其他语言,翻译成简体中文。只输出翻译结果,不要解释:\n\n{{text}}"
    static let defaultSystemPrompt = "你是一个简洁高效的助手,直接给出答案,避免冗余的客套话。"

    // AI 接入配置:多供应商
    @Published var providers: [AIProvider] = []
    @Published var activeProviderID: String = ""   // 当前激活的供应商 id
    @Published var activeModel: String = ""        // 当前激活的模型名
    @Published var temperature: Double = 0.3
    @Published var settingsSchemaVersion: Int = AppSettings.currentSchemaVersion

    // 快捷键(旧:仅保留用于迁移与「快捷输入面板」)
    @Published var askHotKey: HotKeyCombo = .askDefault
    @Published var translateHotKey: HotKeyCombo = .translateDefault
    /// 快捷输入面板(不依赖选中文字)的全局快捷键
    @Published var quickPanelHotKey: HotKeyCombo = .quickPanelDefault

    // 自定义动作(提问/翻译/润色/总结/解释代码…)
    @Published var actions: [AIAction] = AIAction.defaults()

    // Prompt 模板,{{text}} 会被替换为选中文字(systemPrompt 仍全局生效)
    @Published var askPrompt: String = AppSettings.defaultAskPrompt
    @Published var translatePrompt: String = AppSettings.defaultTranslatePrompt
    @Published var systemPrompt: String = AppSettings.defaultSystemPrompt

    // 行为
    @Published var useAXFirst: Bool = true   // 优先用辅助功能取词
    @Published var showDockIcon: Bool = true // 在 Dock 显示图标(可点击打开设置)
    @Published var typewriterSpeed: TypewriterSpeed = .normal // 打字机动画速度
    @Published var autoRouteEnabled: Bool = false
    @Published var fallbackEnabled: Bool = true
    @Published var routingPreference: AIRoutingPreference = .balanced
    @Published var workModePreset: WorkModePreset = .standard
    @Published var privacyPreviewEnabled: Bool = false
    @Published var redactionEnabled: Bool = false
    @Published var redactionRules: [PrivacyRedactionRule] = PrivacyRedactionRule.defaults()
    @Published var contextProfiles: [ContextProfile] = ContextProfile.defaults()
    @Published var activeContextProfileID: String = ""

    // 历史 / 引导 / 窗口尺寸
    @Published var history: [HistoryEntry] = []
    @Published var historyLimit: Int = 50
    @Published var historyContentStorage: HistoryContentStorage = .full
    @Published var savedHistoryFilters: [SavedHistoryFilter] = []
    @Published var onboardingDone: Bool = false
    @Published var panelWidth: Double = AppSettings.defaultPanelWidth
    @Published var panelHeight: Double = AppSettings.defaultPanelHeight
    // 统计(#11) 动作使用次数,key = 动作名
    @Published var actionUsageCounts: [String: Int] = [:]
    // iCloud 同步开关(#9)
    @Published var iCloudSyncEnabled: Bool = false

    // MARK: - 当前激活配置(兼容旧的扁平访问方式,供 AIClient / ModelLoader 使用)

    /// 当前激活的供应商。只返回已启用供应商,避免禁用项继续参与请求。
    var activeProvider: AIProvider? {
        providers.first(where: { $0.id == activeProviderID && $0.isEnabled })
            ?? providers.first(where: { $0.isEnabled })
    }

    var apiProtocol: APIProtocol { activeProvider?.apiProtocol ?? .openAI }
    var baseURL: String { activeProvider?.baseURL ?? "" }
    var apiKey: String { activeProvider?.apiKey ?? "" }
    var model: String {
        guard let provider = activeProvider else { return "" }
        let enabledModels = provider.enabledModelNames
        if enabledModels.contains(activeModel) {
            return activeModel
        }
        return enabledModels.first ?? ""
    }

    var modelSelectionTitle: String {
        model.isEmpty ? "选择模型" : model
    }

    var activeContextProfile: ContextProfile? {
        contextProfiles.first {
            $0.id == activeContextProfileID &&
            $0.isEnabled &&
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var effectiveSystemPrompt: String {
        let base = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile = activeContextProfile else { return base }
        let context = profile.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isEmpty else { return base }
        let profileName = MarkdownExportSafety.metadata(profile.name,
                                                         fallback: "未命名上下文",
                                                         maxLength: 80)
        let block = """
        当前上下文包: \(profileName)
        \(context)
        """
        return [base, block].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    var effectiveSystemPromptMarkdownExport: String {
        let prompt = effectiveSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextName = MarkdownExportSafety.metadata(activeContextProfile?.name,
                                                        fallback: "无",
                                                        maxLength: 80)
        return """
        # SnapAI 实际系统提示

        - 当前上下文包: \(contextName)
        - 字符数: \(prompt.count)

        ## 内容

        \(prompt.isEmpty ? "无内容" : prompt)
        """
    }

    var contextStatusSummary: ContextStatusSummary {
        ContextStatusSummary.make(settings: self)
    }

    var currentWorkModeBehavior: WorkModeBehavior {
        WorkModeBehavior(privacyPreviewEnabled: privacyPreviewEnabled,
                         redactionEnabled: redactionEnabled,
                         historyContentStorage: historyContentStorage,
                         autoRouteEnabled: autoRouteEnabled,
                         fallbackEnabled: fallbackEnabled,
                         routingPreference: routingPreference)
    }

    var matchingWorkModePreset: WorkModePreset? {
        WorkModePreset.allCases.first { $0.behavior == currentWorkModeBehavior }
    }

    var prefersLocalModelRoutes: Bool {
        matchingWorkModePreset == .privacy ||
        (privacyPreviewEnabled && redactionEnabled && historyContentStorage == .metadataOnly)
    }

    var workModeStatusTitle: String {
        matchingWorkModePreset?.title ?? "自定义模式"
    }

    var workModeStatusDetail: String {
        if let mode = matchingWorkModePreset {
            return mode.summary
        }
        return "当前隐私、历史或路由设置已偏离预设。"
    }

    func applyWorkMode(_ mode: WorkModePreset) {
        let behavior = mode.behavior
        workModePreset = mode
        privacyPreviewEnabled = behavior.privacyPreviewEnabled
        redactionEnabled = behavior.redactionEnabled
        historyContentStorage = behavior.historyContentStorage
        autoRouteEnabled = behavior.autoRouteEnabled
        fallbackEnabled = behavior.fallbackEnabled
        routingPreference = behavior.routingPreference
    }

    var contextStatusMarkdownExport: String {
        let summary = contextStatusSummary
        return """
        # SnapAI 上下文状态

        - 上下文包总数: \(summary.profileCount)
        - 可用上下文包: \(summary.usableProfileCount)
        - 当前上下文包: \(MarkdownExportSafety.metadata(summary.activeProfileName, fallback: "无", maxLength: 80))
        - 当前上下文字符数: \(summary.activeContextCharacterCount)
        - 全局 System Prompt 字符数: \(summary.globalSystemPromptCharacterCount)
        - 实际 System Prompt 字符数: \(summary.effectiveSystemPromptCharacterCount)
        """
    }

    func hasContextProfile(named name: String) -> Bool {
        contextProfileIndex(named: name) != nil
    }

    @discardableResult
    func upsertContextProfile(from draft: HistoryContextProfileDraft) -> ContextProfileUpsertResult {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "历史上下文" : trimmedName
        if let index = contextProfileIndex(named: resolvedName) {
            contextProfiles[index].name = resolvedName
            contextProfiles[index].content = draft.content
            contextProfiles[index].isEnabled = true
            activeContextProfileID = contextProfiles[index].id
            save()
            return ContextProfileUpsertResult(profile: contextProfiles[index], didUpdate: true)
        }

        let profile = ContextProfile(name: resolvedName,
                                     content: draft.content,
                                     isEnabled: true)
        contextProfiles.append(profile)
        activeContextProfileID = profile.id
        save()
        return ContextProfileUpsertResult(profile: profile, didUpdate: false)
    }

    /// 选中某个供应商的某个模型为当前激活
    func activate(providerID: String, model: String, recordManualPreference: Bool = false) {
        activeProviderID = providerID
        activeModel = model
        normalizeActive()
        if recordManualPreference {
            RoutingMetricsStore.shared.recordManualPreference(providerID: activeProviderID,
                                                              modelName: activeModel)
        }
        save()
    }

    /// 确保激活态有效:激活的供应商/模型若失效,自动落到第一个可用的启用项
    func normalizeActive() {
        // 供应商:必须存在且启用。没有启用项时明确置空,让请求层给出可读错误。
        guard let firstEnabled = providers.first(where: { $0.isEnabled }) else {
            activeProviderID = ""
            activeModel = ""
            return
        }
        if !providers.contains(where: { $0.id == activeProviderID && $0.isEnabled }) {
            activeProviderID = firstEnabled.id
        }
        // 模型:必须在激活供应商的启用模型里
        if let p = activeProvider {
            let enabled = p.enabledModelNames
            if !enabled.contains(activeModel) {
                activeModel = enabled.first ?? ""
            }
        } else {
            activeModel = ""
        }
    }

    private func contextProfileIndex(named name: String) -> Int? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedName.isEmpty else { return nil }
        return contextProfiles.firstIndex {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName
        }
    }

    /// 所有「启用供应商 → 启用模型」的扁平条目,用于菜单栏快速切换
    var switchableEntries: [(provider: AIProvider, model: String)] {
        var result: [(AIProvider, String)] = []
        for p in providers where p.isEnabled {
            for m in p.enabledModelNames {
                result.append((p, m))
            }
        }
        return result
    }

    /// 启用的动作(用于菜单/快捷键注册)
    var enabledActions: [AIAction] { actions.filter { $0.isEnabled } }

    // MARK: - 历史记录

    /// 追加一条历史并裁剪到上限
    func addHistory(action: String, source: String, output: String,
                    provider: String, model: String, tags: [String] = [],
                    contentStorage: HistoryContentStorage? = nil) {
        guard historyLimit > 0 else { return }
        let payload = historyPayload(source: source,
                                     output: output,
                                     tags: tags,
                                     contentStorage: contentStorage ?? historyContentStorage)
        let entry = HistoryEntry(actionName: Self.limitedImportedString(action.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                        maxLength: AIAction.maxNameLength,
                                                                        fallback: "未命名动作"),
                                 source: payload.source,
                                 output: payload.output,
                                 provider: Self.limitedImportedString(provider.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                      maxLength: Self.importedProviderNameLimit,
                                                                      fallback: ""),
                                 model: Self.limitedImportedString(model.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                   maxLength: Self.importedModelNameLimit,
                                                                   fallback: ""),
                                 tags: payload.tags)
        history.insert(entry, at: 0)
        if history.count > historyLimit {
            history = Array(history.prefix(historyLimit))
        }
        HistoryStore.shared.upsert(entry, limit: historyLimit)
        save()
    }

    func clearHistory() {
        history.removeAll()
        HistoryStore.shared.deleteAll()
        save()
    }

    func deleteHistory(id: String) {
        history.removeAll { $0.id == id }
        HistoryStore.shared.delete(id: id)
        save()
    }

    func toggleHistoryFavorite(id: String) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        history[idx].isFavorite.toggle()
        HistoryStore.shared.upsert(history[idx], limit: historyLimit)
        save()
    }

    func updateHistoryTags(id: String, tags: [String]) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        history[idx].tags = Self.historyTags(tags)
        HistoryStore.shared.upsert(history[idx], limit: historyLimit)
        save()
    }

    @discardableResult
    func upsertSavedHistoryFilter(name: String,
                                  criteria: HistoryFilterCriteria,
                                  date: Date = Date()) -> SavedHistoryFilter? {
        let safeName = Self.sanitizedSavedHistoryFilterName(name)
        guard !safeName.isEmpty else { return nil }
        let safeCriteria = Self.sanitizedHistoryFilterCriteria(criteria)
        let nameKey = Self.savedHistoryFilterNameKey(safeName)

        var filter: SavedHistoryFilter
        if let index = savedHistoryFilters.firstIndex(where: { Self.savedHistoryFilterNameKey($0.name) == nameKey }) {
            filter = savedHistoryFilters[index]
            filter.name = safeName
            filter.criteria = safeCriteria
            filter.updatedAt = date
            savedHistoryFilters.remove(at: index)
        } else {
            filter = SavedHistoryFilter(name: safeName,
                                        criteria: safeCriteria,
                                        createdAt: date,
                                        updatedAt: date)
        }
        savedHistoryFilters.insert(filter, at: 0)
        savedHistoryFilters = Self.sanitizedStoredSavedHistoryFilters(savedHistoryFilters)
        save()
        return savedHistoryFilters.first { $0.id == filter.id }
    }

    func deleteSavedHistoryFilter(id: String) {
        savedHistoryFilters.removeAll { $0.id == id }
        save()
    }

    func recordActionUsage(actionName: String) {
        let name = Self.limitedImportedString(actionName.trimmingCharacters(in: .whitespacesAndNewlines),
                                              maxLength: AIAction.maxNameLength,
                                              fallback: "未命名动作")
        let current = actionUsageCounts[name] ?? 0
        actionUsageCounts[name] = current >= Self.importedActionUsageCountRange.upperBound
            ? Self.importedActionUsageCountRange.upperBound
            : max(0, current) + 1
        actionUsageCounts = Self.sanitizedStoredActionUsageCounts(actionUsageCounts)
    }

    enum CodingKeys: String, CodingKey {
        // 新:多供应商
        case providers, activeProviderID, activeModel
        case temperature, settingsSchemaVersion
        case askHotKey, translateHotKey, quickPanelHotKey
        case actions
        case askPrompt, translatePrompt, systemPrompt, useAXFirst, showDockIcon
        case typewriterSpeed
        case autoRouteEnabled, fallbackEnabled, routingPreference, workModePreset
        case privacyPreviewEnabled, redactionEnabled, redactionRules
        case contextProfiles, activeContextProfileID
        case history, historyLimit, historyContentStorage, savedHistoryFilters, onboardingDone, panelWidth, panelHeight
        case actionUsageCounts, iCloudSyncEnabled
        // 旧:单配置(仅用于迁移,不再写出)
        case apiProtocol, baseURL, apiKey, model
    }

    init() {
        providers = [AIProvider.preset(.openAI)]
        if let first = providers.first {
            activeProviderID = first.id
            activeModel = first.enabledModelNames.first ?? ""
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = (try? c.decode(Int.self, forKey: .settingsSchemaVersion)) ?? 1
        settingsSchemaVersion = decodedSchemaVersion
        temperature = Self.clampedTemperature((try? c.decode(Double.self, forKey: .temperature)) ?? 0.3)
        askHotKey = (try? c.decode(HotKeyCombo.self, forKey: .askHotKey)) ?? .askDefault
        translateHotKey = (try? c.decode(HotKeyCombo.self, forKey: .translateHotKey)) ?? .translateDefault
        let decodedAskPrompt = try? c.decode(String.self, forKey: .askPrompt)
        askPrompt = Self.sanitizedPrompt(decodedAskPrompt,
                                         fallback: Self.defaultAskPrompt)
        if let decodedAskPrompt, askPrompt != decodedAskPrompt {
            needsPostLoadSave = true
        }
        let decodedTranslatePrompt = try? c.decode(String.self, forKey: .translatePrompt)
        translatePrompt = Self.sanitizedPrompt(decodedTranslatePrompt,
                                               fallback: Self.defaultTranslatePrompt,
                                               migrateOldTranslateDefault: true)
        if let decodedTranslatePrompt, translatePrompt != decodedTranslatePrompt {
            needsPostLoadSave = true
        }
        let decodedSystemPrompt = try? c.decode(String.self, forKey: .systemPrompt)
        systemPrompt = Self.sanitizedPrompt(decodedSystemPrompt,
                                            fallback: Self.defaultSystemPrompt,
                                            allowEmpty: true,
                                            maxLength: Self.importedSystemPromptLimit)
        if let decodedSystemPrompt, systemPrompt != decodedSystemPrompt {
            needsPostLoadSave = true
        }
        useAXFirst = (try? c.decode(Bool.self, forKey: .useAXFirst)) ?? true
        showDockIcon = (try? c.decode(Bool.self, forKey: .showDockIcon)) ?? true
        typewriterSpeed = (try? c.decode(TypewriterSpeed.self, forKey: .typewriterSpeed)) ?? .normal
        autoRouteEnabled = (try? c.decode(Bool.self, forKey: .autoRouteEnabled)) ?? false
        fallbackEnabled = (try? c.decode(Bool.self, forKey: .fallbackEnabled)) ?? true
        routingPreference = (try? c.decode(AIRoutingPreference.self, forKey: .routingPreference)) ?? .balanced
        workModePreset = (try? c.decode(WorkModePreset.self, forKey: .workModePreset)) ?? .standard
        privacyPreviewEnabled = (try? c.decode(Bool.self, forKey: .privacyPreviewEnabled)) ?? false
        redactionEnabled = (try? c.decode(Bool.self, forKey: .redactionEnabled)) ?? false
        let decodedRedactionRules = (try? c.decode([PrivacyRedactionRule].self, forKey: .redactionRules)) ?? PrivacyRedactionRule.defaults()
        redactionRules = Self.sanitizedStoredRedactionRules(decodedRedactionRules)
        if redactionRules != decodedRedactionRules {
            needsPostLoadSave = true
        }
        let decodedContextProfiles = (try? c.decode([ContextProfile].self, forKey: .contextProfiles)) ?? ContextProfile.defaults()
        let decodedActiveContextProfileID = (try? c.decode(String.self, forKey: .activeContextProfileID)) ?? ""
        let sanitizedContext = Self.sanitizedStoredContextProfiles(decodedContextProfiles,
                                                                   activeID: decodedActiveContextProfileID)
        contextProfiles = sanitizedContext.profiles
        activeContextProfileID = sanitizedContext.activeID
        if contextProfiles != decodedContextProfiles || activeContextProfileID != decodedActiveContextProfileID {
            needsPostLoadSave = true
        }

        quickPanelHotKey = (try? c.decode(HotKeyCombo.self, forKey: .quickPanelHotKey))
            ?? .quickPanelDefault

        // 动作:有则用,无则用默认 5 个;并把旧的 ask/translate 快捷键迁移到对应动作
        if let acts = try? c.decode([AIAction].self, forKey: .actions), !acts.isEmpty {
            actions = acts
        } else {
            var defs = AIAction.defaults()
            if let ah = try? c.decode(HotKeyCombo.self, forKey: .askHotKey), defs.indices.contains(0) {
                defs[0].hotKey = ah
            }
            if let th = try? c.decode(HotKeyCombo.self, forKey: .translateHotKey), defs.indices.contains(1) {
                defs[1].hotKey = th
            }
            // 旧的自定义提问/翻译模板若被改过,沿用到对应动作
            if let ap = try? c.decode(String.self, forKey: .askPrompt),
               ap != Self.defaultAskPrompt,
               defs.indices.contains(0) {
                defs[0].prompt = Self.sanitizedPrompt(ap,
                                                      fallback: Self.defaultAskPrompt)
            }
            actions = defs
        }
        applyMigrations(from: decodedSchemaVersion)
        actions = Self.sanitizedImportedActions(actions)

        let decodedHistory = (try? c.decode([HistoryEntry].self, forKey: .history)) ?? []
        let decodedHistoryLimit = (try? c.decode(Int.self, forKey: .historyLimit)) ?? 50
        historyLimit = Self.clampedHistoryLimit(decodedHistoryLimit)
        history = Self.sanitizedStoredHistory(decodedHistory, limit: historyLimit)
        if history != decodedHistory || historyLimit != decodedHistoryLimit {
            needsPostLoadSave = true
        }
        historyContentStorage = (try? c.decode(HistoryContentStorage.self, forKey: .historyContentStorage)) ?? .full
        let decodedSavedHistoryFilters = (try? c.decode([SavedHistoryFilter].self, forKey: .savedHistoryFilters)) ?? []
        savedHistoryFilters = Self.sanitizedStoredSavedHistoryFilters(decodedSavedHistoryFilters)
        if savedHistoryFilters != decodedSavedHistoryFilters {
            needsPostLoadSave = true
        }
        // 已有存档的老用户视为已完成引导(缺该键时默认 true);全新安装走 init() 默认 false
        onboardingDone = (try? c.decode(Bool.self, forKey: .onboardingDone)) ?? true
        let decodedPanelWidth = (try? c.decode(Double.self, forKey: .panelWidth)) ?? Self.defaultPanelWidth
        let decodedPanelHeight = (try? c.decode(Double.self, forKey: .panelHeight)) ?? Self.defaultPanelHeight
        panelWidth = Self.clampedPanelWidth(decodedPanelWidth)
        panelHeight = Self.clampedPanelHeight(decodedPanelHeight)
        if panelWidth != decodedPanelWidth || panelHeight != decodedPanelHeight {
            needsPostLoadSave = true
        }
        let decodedActionUsageCounts = (try? c.decode([String: Int].self, forKey: .actionUsageCounts)) ?? [:]
        actionUsageCounts = Self.sanitizedStoredActionUsageCounts(decodedActionUsageCounts)
        if actionUsageCounts != decodedActionUsageCounts {
            needsPostLoadSave = true
        }
        iCloudSyncEnabled = (try? c.decode(Bool.self, forKey: .iCloudSyncEnabled)) ?? false

        if let list = try? c.decode([AIProvider].self, forKey: .providers), !list.isEmpty {
            // 新格式
            providers = Self.sanitizedStoredProviders(list)
            let decodedActiveProviderID = (try? c.decode(String.self, forKey: .activeProviderID)) ?? list.first?.id ?? ""
            let decodedActiveModel = (try? c.decode(String.self, forKey: .activeModel)) ?? ""
            activeProviderID = Self.providerIDAfterProviderSanitization(originalProviders: list,
                                                                        sanitizedProviders: providers,
                                                                        providerID: decodedActiveProviderID,
                                                                        modelName: decodedActiveModel)
            activeModel = Self.sanitizedActiveModelName(decodedActiveModel)
            if providers != list {
                needsPostLoadSave = true
            }
            if activeProviderID != decodedActiveProviderID || activeModel != decodedActiveModel {
                needsPostLoadSave = true
            }
            let actionsBeforeProviderRemap = actions
            actions = Self.sanitizedImportedActions(actions,
                                                    originalProviders: list,
                                                    sanitizedProviders: providers)
            if actions != actionsBeforeProviderRemap {
                needsPostLoadSave = true
            }
        } else {
            // 旧格式迁移:把单一配置包装成一个供应商
            let proto = (try? c.decode(APIProtocol.self, forKey: .apiProtocol)) ?? .openAI
            let url = (try? c.decode(String.self, forKey: .baseURL)) ?? "https://api.openai.com/v1"
            let key = (try? c.decode(String.self, forKey: .apiKey)) ?? ""
            let mdl = (try? c.decode(String.self, forKey: .model)) ?? "gpt-4o-mini"
            var p = AIProvider(name: "我的配置", apiProtocol: proto, baseURL: url, apiKey: key)
            if !mdl.isEmpty { p.models = [AIModelEntry(name: mdl)] }
            providers = Self.sanitizedStoredProviders([p])
            activeProviderID = providers.first?.id ?? p.id
            activeModel = Self.sanitizedActiveModelName(mdl)
            needsPostLoadSave = true
        }
        normalizeActive()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(providers, forKey: .providers)
        try c.encode(activeProviderID, forKey: .activeProviderID)
        try c.encode(activeModel, forKey: .activeModel)
        try c.encode(temperature, forKey: .temperature)
        try c.encode(settingsSchemaVersion, forKey: .settingsSchemaVersion)
        try c.encode(askHotKey, forKey: .askHotKey)
        try c.encode(translateHotKey, forKey: .translateHotKey)
        try c.encode(quickPanelHotKey, forKey: .quickPanelHotKey)
        try c.encode(actions, forKey: .actions)
        try c.encode(askPrompt, forKey: .askPrompt)
        try c.encode(translatePrompt, forKey: .translatePrompt)
        try c.encode(systemPrompt, forKey: .systemPrompt)
        try c.encode(useAXFirst, forKey: .useAXFirst)
        try c.encode(showDockIcon, forKey: .showDockIcon)
        try c.encode(typewriterSpeed, forKey: .typewriterSpeed)
        try c.encode(autoRouteEnabled, forKey: .autoRouteEnabled)
        try c.encode(fallbackEnabled, forKey: .fallbackEnabled)
        try c.encode(routingPreference, forKey: .routingPreference)
        try c.encode(workModePreset, forKey: .workModePreset)
        try c.encode(privacyPreviewEnabled, forKey: .privacyPreviewEnabled)
        try c.encode(redactionEnabled, forKey: .redactionEnabled)
        try c.encode(redactionRules, forKey: .redactionRules)
        try c.encode(contextProfiles, forKey: .contextProfiles)
        try c.encode(activeContextProfileID, forKey: .activeContextProfileID)
        // History content lives in HistoryStore. Keep decoding this key for
        // legacy migration, but never write it back into UserDefaults.
        try c.encode(historyLimit, forKey: .historyLimit)
        try c.encode(historyContentStorage, forKey: .historyContentStorage)
        try c.encode(savedHistoryFilters, forKey: .savedHistoryFilters)
        try c.encode(onboardingDone, forKey: .onboardingDone)
        try c.encode(panelWidth, forKey: .panelWidth)
        try c.encode(panelHeight, forKey: .panelHeight)
        try c.encode(actionUsageCounts, forKey: .actionUsageCounts)
        try c.encode(iCloudSyncEnabled, forKey: .iCloudSyncEnabled)
    }

    private static let storeKey = "SnapAI.settings.v1"

    static func load() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            let hadPlaintext = String(data: data, encoding: .utf8)?.contains("\"apiKey\"") ?? false
            s.loadKeysFromKeychain()
            s.loadHistoryFromLocalStoreOrMigrate()
            // 旧版本可能把明文 Key 存在 JSON 里;迁移后立即重写一次以彻底清除明文
            if hadPlaintext || s.needsPostLoadSave { s.save() }
            return s
        }
        let settings = AppSettings()
        settings.loadHistoryFromLocalStoreOrMigrate()
        return settings
    }

    /// 已写入 Keychain 的 Key 快照,避免每次 save() 都重复写(打字时 commit 很频繁)
    private var keychainCache: [String: String] = [:]
    private var needsPostLoadSave = false

    private func applyMigrations(from version: Int) {
        guard version < Self.currentSchemaVersion else { return }
        if version < 2 {
            applyMissingDefaultHotKeys()
        }
        settingsSchemaVersion = Self.currentSchemaVersion
        needsPostLoadSave = true
    }

    private func applyMissingDefaultHotKeys() {
        let defaults = Dictionary(uniqueKeysWithValues: AIAction.defaults().compactMap { action in
            action.hotKey.map { (action.name, $0) }
        })
        for idx in actions.indices {
            guard actions[idx].hotKey == nil,
                  let hk = defaults[actions[idx].name] else { continue }
            actions[idx].hotKey = hk
        }
    }

    /// 从 Keychain 回填各供应商的 apiKey(decode 后它们都是空字符串)
    private func loadKeysFromKeychain() {
        for i in providers.indices {
            // 迁移分支可能已在内存里带了明文 key(来自旧 JSON),优先保留并落 Keychain
            if providers[i].apiKey.isEmpty {
                providers[i].apiKey = Keychain.apiKey(for: providers[i].id)
            } else {
                Keychain.setAPIKey(providers[i].apiKey, for: providers[i].id)
            }
            keychainCache[providers[i].id] = providers[i].apiKey
        }
    }

    func save() {
        // 仅当 Key 发生变化时才写 Keychain(避免打字时频繁写入)
        for p in providers where keychainCache[p.id] != p.apiKey {
            Keychain.setAPIKey(p.apiKey, for: p.id)
            keychainCache[p.id] = p.apiKey
        }
        let sanitizedHistory = Self.sanitizedStoredHistory(history, limit: historyLimit)
        if sanitizedHistory != history {
            history = sanitizedHistory
            HistoryStore.shared.replaceAll(history, limit: historyLimit)
        }
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    private func loadHistoryFromLocalStoreOrMigrate() {
        let storedHistory = HistoryStore.shared.load(limit: historyLimit)
        if !storedHistory.isEmpty {
            history = storedHistory
            return
        }
        if !history.isEmpty {
            HistoryStore.shared.replaceAll(history, limit: historyLimit)
        }
    }

    func exportConfigurationData() -> Data? {
        guard let data = try? JSONEncoder().encode(self),
              let exportSettings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return nil
        }
        exportSettings.history = []
        exportSettings.actionUsageCounts = [:]
        exportSettings.panelWidth = Self.defaultPanelWidth
        exportSettings.panelHeight = Self.defaultPanelHeight
        exportSettings.iCloudSyncEnabled = false
        exportSettings.onboardingDone = true
        return try? JSONEncoder().encode(exportSettings)
    }

    static func providersForImportedConfiguration(_ providers: [AIProvider],
                                                  keyResolver: (String) -> String = { Keychain.apiKey(for: $0) }) -> [AIProvider] {
        var seenProviderIDs = Set<String>()
        return providers.prefix(importedProviderLimit).map { provider in
            let originalID = provider.id.trimmingCharacters(in: .whitespacesAndNewlines)
            var copy = provider
            copy.id = uniqueImportedID(provider.id, seenIDs: &seenProviderIDs)
            copy.name = limitedImportedString(provider.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                              maxLength: importedProviderNameLimit,
                                              fallback: "新供应商")
            copy.baseURL = limitedImportedString(provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                                 maxLength: importedProviderBaseURLLimit,
                                                 fallback: "")
            copy.apiKey = keyResolver(originalID.isEmpty ? copy.id : originalID)
            copy.models = sanitizedImportedModels(provider.models)
            copy.temperature = sanitizedImportedProviderTemperature(provider.temperature)
            copy.maxTokens = sanitizedImportedMaxTokens(provider.maxTokens)
            copy.requestTimeout = sanitizedImportedRequestTimeout(provider.requestTimeout)
            return copy
        }
    }

    static func importedProviderConfiguration(_ providers: [AIProvider],
                                              activeProviderID: String,
                                              activeModel: String,
                                              keyResolver: (String) -> String = { Keychain.apiKey(for: $0) })
    -> (providers: [AIProvider], activeProviderID: String, activeModel: String) {
        let sanitizedProviders = providersForImportedConfiguration(providers, keyResolver: keyResolver)
        let sanitizedActiveModel = sanitizedActiveModelName(activeModel)
        let sanitizedActiveProviderID = providerIDAfterProviderSanitization(
            originalProviders: providers,
            sanitizedProviders: sanitizedProviders,
            providerID: activeProviderID,
            modelName: sanitizedActiveModel
        )
        return (sanitizedProviders, sanitizedActiveProviderID, sanitizedActiveModel)
    }

    static func sanitizedStoredProviders(_ providers: [AIProvider]) -> [AIProvider] {
        var seenProviderIDs = Set<String>()
        return providers.prefix(importedProviderLimit).map { provider in
            var copy = provider
            let trimmedID = provider.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedID.isEmpty || seenProviderIDs.contains(provider.id) {
                copy.id = uniqueImportedID(trimmedID, seenIDs: &seenProviderIDs)
            } else {
                seenProviderIDs.insert(provider.id)
            }
            copy.name = limitedImportedString(provider.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                              maxLength: importedProviderNameLimit,
                                              fallback: "新供应商")
            copy.baseURL = limitedImportedString(provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                                 maxLength: importedProviderBaseURLLimit,
                                                 fallback: "")
            copy.models = sanitizedImportedModels(provider.models)
            copy.temperature = sanitizedImportedProviderTemperature(provider.temperature)
            copy.maxTokens = sanitizedImportedMaxTokens(provider.maxTokens)
            copy.requestTimeout = sanitizedImportedRequestTimeout(provider.requestTimeout)
            return copy
        }
    }

    func normalizeImportedConfiguration() {
        let originalProviders = providers
        let providerConfig = Self.importedProviderConfiguration(providers,
                                                                activeProviderID: activeProviderID,
                                                                activeModel: activeModel)
        providers = providerConfig.providers
        activeProviderID = providerConfig.activeProviderID
        activeModel = providerConfig.activeModel
        temperature = Self.clampedTemperature(temperature)
        actions = Self.sanitizedImportedActions(actions,
                                                originalProviders: originalProviders,
                                                sanitizedProviders: providers)
        askPrompt = Self.sanitizedPrompt(askPrompt,
                                         fallback: Self.defaultAskPrompt)
        translatePrompt = Self.sanitizedPrompt(translatePrompt,
                                               fallback: Self.defaultTranslatePrompt,
                                               migrateOldTranslateDefault: true)
        systemPrompt = Self.sanitizedPrompt(systemPrompt,
                                            fallback: Self.defaultSystemPrompt,
                                            allowEmpty: true,
                                            maxLength: Self.importedSystemPromptLimit)
        historyLimit = Self.clampedHistoryLimit(historyLimit)
        savedHistoryFilters = Self.sanitizedStoredSavedHistoryFilters(savedHistoryFilters)
        redactionRules = Self.sanitizedImportedRedactionRules(redactionRules)
        let context = Self.sanitizedImportedContextProfiles(contextProfiles,
                                                            activeID: activeContextProfileID)
        contextProfiles = context.profiles
        activeContextProfileID = context.activeID
        normalizeActive()
    }

    static func clampedTemperature(_ value: Double) -> Double {
        guard value.isFinite else { return 0.3 }
        return min(max(value, 0), 1)
    }

    static func clampedHistoryLimit(_ value: Int) -> Int {
        min(max(value, importedHistoryLimitRange.lowerBound), importedHistoryLimitRange.upperBound)
    }

    static func clampedPanelWidth(_ value: Double) -> Double {
        clampedPanelDimension(value,
                              fallback: defaultPanelWidth,
                              range: importedPanelWidthRange)
    }

    static func clampedPanelHeight(_ value: Double) -> Double {
        clampedPanelDimension(value,
                              fallback: defaultPanelHeight,
                              range: importedPanelHeightRange)
    }

    private static func clampedPanelDimension(_ value: Double,
                                              fallback: Double,
                                              range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func sanitizedImportedModels(_ models: [AIModelEntry]) -> [AIModelEntry] {
        var seenNames = Set<String>()
        return models.prefix(importedModelLimit).compactMap { model in
            let name = limitedImportedString(model.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                             maxLength: importedModelNameLimit,
                                             fallback: "")
            guard !name.isEmpty,
                  seenNames.insert(name).inserted else { return nil }
            return AIModelEntry(name: name, enabled: model.enabled)
        }
    }

    static func sanitizedImportedActions(_ actions: [AIAction]) -> [AIAction] {
        guard !actions.isEmpty else { return AIAction.defaults() }
        var seenIDs = Set<String>()
        let cleaned = actions.prefix(importedActionLimit).map { action in
            var copy = action
            copy.id = uniqueImportedID(action.id, seenIDs: &seenIDs)
            copy.name = limitedImportedString(action.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                              maxLength: AIAction.maxNameLength,
                                              fallback: "新动作")
            copy.icon = limitedImportedString(action.icon.trimmingCharacters(in: .whitespacesAndNewlines),
                                              maxLength: AIAction.maxIconLength,
                                              fallback: "wand.and.stars")
            copy.group = limitedImportedString(action.group.trimmingCharacters(in: .whitespacesAndNewlines),
                                               maxLength: AIAction.maxGroupLength,
                                               fallback: "")
            copy.prompt = limitedImportedString(action.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                                                maxLength: AIAction.maxPromptLength,
                                                fallback: "{{text}}")
            copy.thinkingBudget = AIAction.sanitizedThinkingBudget(action.thinkingBudget)
            copy.providerID = sanitizedOptionalImportedString(action.providerID)
            copy.modelOverride = sanitizedActionModelOverride(action.modelOverride)
            return copy
        }
        return cleaned.isEmpty ? AIAction.defaults() : cleaned
    }

    static func sanitizedImportedActions(_ actions: [AIAction],
                                         originalProviders: [AIProvider],
                                         sanitizedProviders: [AIProvider]) -> [AIAction] {
        sanitizedImportedActions(actions).map { action in
            var copy = action
            if let providerID = action.providerID {
                copy.providerID = providerIDAfterProviderSanitization(originalProviders: originalProviders,
                                                                      sanitizedProviders: sanitizedProviders,
                                                                      providerID: providerID,
                                                                      modelName: action.modelOverride)
                if let override = copy.modelOverride,
                   let mappedProvider = sanitizedProviders.first(where: { $0.id == copy.providerID }),
                   !mappedProvider.enabledModelNames.contains(override) {
                    copy.modelOverride = nil
                }
            }
            return copy
        }
    }

    static func sanitizedStoredHistory(_ entries: [HistoryEntry], limit: Int) -> [HistoryEntry] {
        let cappedLimit = clampedHistoryLimit(limit)
        guard cappedLimit > 0 else { return [] }
        var seenIDs = Set<String>()
        return entries.prefix(cappedLimit).map { entry in
            var copy = entry
            copy.id = uniqueImportedID(entry.id, seenIDs: &seenIDs)
            copy.actionName = limitedImportedString(entry.actionName.trimmingCharacters(in: .whitespacesAndNewlines),
                                                    maxLength: AIAction.maxNameLength,
                                                    fallback: "未命名动作")
            copy.provider = limitedImportedString(entry.provider.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  maxLength: importedProviderNameLimit,
                                                  fallback: "")
            copy.model = limitedImportedString(entry.model.trimmingCharacters(in: .whitespacesAndNewlines),
                                               maxLength: importedModelNameLimit,
                                               fallback: "")
            let sourcePayload = limitedHistoryText(entry.source,
                                                   maxLength: historySourceCharacterLimit)
            let outputPayload = limitedHistoryText(entry.output,
                                                   maxLength: historyOutputCharacterLimit)
            copy.source = sourcePayload.text
            copy.output = outputPayload.text
            var appendedTags: [String] = []
            if sourcePayload.wasTruncated || entry.displayTags.contains(PrivacyHistoryTag.sourceTruncated) {
                appendedTags.append(PrivacyHistoryTag.sourceTruncated)
            }
            if outputPayload.wasTruncated || entry.displayTags.contains(PrivacyHistoryTag.outputTruncated) {
                appendedTags.append(PrivacyHistoryTag.outputTruncated)
            }
            copy.tags = historyTags(entry.tags, appending: appendedTags)
            return copy
        }
    }

    static func sanitizedStoredSavedHistoryFilters(_ filters: [SavedHistoryFilter]) -> [SavedHistoryFilter] {
        var seenIDs = Set<String>()
        var seenNames = Set<String>()
        return filters.prefix(importedSavedHistoryFilterLimit).compactMap { filter in
            let safeName = sanitizedSavedHistoryFilterName(filter.name)
            guard !safeName.isEmpty else { return nil }
            let nameKey = savedHistoryFilterNameKey(safeName)
            guard seenNames.insert(nameKey).inserted else { return nil }
            var copy = filter
            copy.id = uniqueImportedID(filter.id, seenIDs: &seenIDs)
            copy.name = safeName
            copy.criteria = sanitizedHistoryFilterCriteria(filter.criteria)
            if copy.updatedAt < copy.createdAt {
                copy.updatedAt = copy.createdAt
            }
            return copy
        }
    }

    static func sanitizedHistoryFilterCriteria(_ criteria: HistoryFilterCriteria) -> HistoryFilterCriteria {
        HistoryFilterCriteria(
            query: limitedImportedString(criteria.query.trimmingCharacters(in: .whitespacesAndNewlines),
                                         maxLength: importedSavedHistoryFilterQueryLimit,
                                         fallback: ""),
            actionFilter: sanitizedHistoryFacet(criteria.actionFilter,
                                                allValue: HistoryFilterCriteria.allActions),
            modelFilter: sanitizedHistoryFacet(criteria.modelFilter,
                                               allValue: HistoryFilterCriteria.allModels),
            tagFilter: sanitizedHistoryFacet(criteria.tagFilter,
                                             allValue: HistoryFilterCriteria.allTags),
            favoriteOnly: criteria.favoriteOnly
        )
    }

    static func sanitizedSavedHistoryFilterName(_ name: String) -> String {
        limitedImportedString(name.trimmingCharacters(in: .whitespacesAndNewlines),
                              maxLength: importedSavedHistoryFilterNameLimit,
                              fallback: "")
    }

    private static func sanitizedHistoryFacet(_ value: String, allValue: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != allValue else { return allValue }
        let limited = limitedImportedString(trimmed,
                                            maxLength: importedSavedHistoryFilterNameLimit,
                                            fallback: allValue)
        return limited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? allValue : limited
    }

    private static func savedHistoryFilterNameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func sanitizedImportedProviderTemperature(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return clampedTemperature(value)
    }

    static func sanitizedImportedMaxTokens(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return min(max(value, importedMaxTokensRange.lowerBound), importedMaxTokensRange.upperBound)
    }

    static func sanitizedImportedRequestTimeout(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return min(max(value, importedRequestTimeoutRange.lowerBound), importedRequestTimeoutRange.upperBound)
    }

    static func sanitizedImportedRedactionRules(_ rules: [PrivacyRedactionRule]) -> [PrivacyRedactionRule] {
        guard !rules.isEmpty else { return [] }
        var seenIDs = Set<String>()
        let cleaned = rules.prefix(importedRedactionRuleLimit).compactMap { rule -> PrivacyRedactionRule? in
            let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty,
                  pattern.count <= importedRedactionPatternLimit,
                  PrivacyFilter.validatePattern(pattern) == nil else {
                return nil
            }

            var copy = rule
            copy.id = uniqueImportedID(rule.id, seenIDs: &seenIDs)
            copy.name = limitedImportedString(rule.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                              maxLength: importedRedactionNameLimit,
                                              fallback: "自定义规则")
            copy.pattern = pattern
            copy.replacement = limitedImportedString(rule.replacement,
                                                     maxLength: importedRedactionReplacementLimit,
                                                     fallback: "")
            return copy
        }
        if cleaned.isEmpty {
            return PrivacyRedactionRule.defaults()
        }
        return isLegacyDefaultRedactionRules(cleaned) ? PrivacyRedactionRule.defaults() : cleaned
    }

    static func sanitizedStoredRedactionRules(_ rules: [PrivacyRedactionRule]) -> [PrivacyRedactionRule] {
        guard !rules.isEmpty else { return [] }
        var seenIDs = Set<String>()
        let cleaned = rules.prefix(importedRedactionRuleLimit).map { rule in
            var copy = rule
            copy.id = uniqueImportedID(rule.id, seenIDs: &seenIDs)
            copy.name = limitedImportedString(rule.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                              maxLength: importedRedactionNameLimit,
                                              fallback: "自定义规则")
            copy.pattern = limitedImportedString(rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines),
                                                 maxLength: importedRedactionPatternLimit,
                                                 fallback: "")
            copy.replacement = limitedImportedString(rule.replacement,
                                                     maxLength: importedRedactionReplacementLimit,
                                                     fallback: "")
            return copy
        }
        return isLegacyDefaultRedactionRules(cleaned) ? PrivacyRedactionRule.defaults() : cleaned
    }

    private static func isLegacyDefaultRedactionRules(_ rules: [PrivacyRedactionRule]) -> Bool {
        let legacy = legacyDefaultRedactionRules()
        guard rules.count == legacy.count else { return false }
        return zip(rules, legacy).allSatisfy { current, expected in
            current.name == expected.name &&
            current.pattern == expected.pattern &&
            current.replacement == expected.replacement &&
            current.isEnabled == expected.isEnabled
        }
    }

    private static func legacyDefaultRedactionRules() -> [PrivacyRedactionRule] {
        [
            PrivacyRedactionRule(
                name: "邮箱地址",
                pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                replacement: "[邮箱]"
            ),
            PrivacyRedactionRule(
                name: "手机号",
                pattern: #"(?<!\d)(?:\+?86[- ]?)?1[3-9]\d{9}(?!\d)"#,
                replacement: "[手机号]"
            ),
            PrivacyRedactionRule(
                name: "疑似 API Key",
                pattern: #"(?i)\b(?:sk(?:-[a-z0-9]+)+|gh[pousr]_[a-z0-9_]{20,}|xox[baprs]-[a-z0-9-]{20,}|(?:api[_-]?key|token|secret)[_:\-= ]+[a-z0-9][a-z0-9._-]{11,})\b"#,
                replacement: "[密钥]"
            )
        ]
    }

    static func sanitizedImportedContextProfiles(_ profiles: [ContextProfile],
                                                 activeID: String) -> (profiles: [ContextProfile], activeID: String) {
        var seenIDs = Set<String>()
        var requestedActiveID = ""
        let cleaned = profiles.prefix(importedContextProfileLimit).compactMap { profile -> ContextProfile? in
            let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedContent = profile.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty || !trimmedContent.isEmpty else { return nil }

            var copy = profile
            copy.id = uniqueImportedID(profile.id, seenIDs: &seenIDs)
            copy.name = limitedImportedString(trimmedName,
                                              maxLength: importedContextNameLimit,
                                              fallback: "未命名上下文")
            copy.content = limitedImportedString(trimmedContent,
                                                 maxLength: importedContextContentLimit,
                                                 fallback: "")
            if requestedActiveID.isEmpty && profile.id == activeID {
                requestedActiveID = copy.id
            }
            return copy
        }

        let active = cleaned.first { profile in
            profile.id == requestedActiveID &&
            profile.isEnabled &&
            !profile.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.id ?? cleaned.first { profile in
            profile.isEnabled &&
            !profile.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.id ?? ""

        return (cleaned, active)
    }

    static func sanitizedStoredContextProfiles(_ profiles: [ContextProfile],
                                               activeID: String) -> (profiles: [ContextProfile], activeID: String) {
        sanitizedImportedContextProfiles(profiles, activeID: activeID)
    }

    static func sanitizedStoredActionUsageCounts(_ counts: [String: Int]) -> [String: Int] {
        var merged: [String: Int] = [:]
        for (name, count) in counts {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty,
                  count >= importedActionUsageCountRange.lowerBound else { continue }
            let safeName = limitedImportedString(trimmedName,
                                                 maxLength: AIAction.maxNameLength,
                                                 fallback: "")
            guard !safeName.isEmpty else { continue }
            let safeCount = min(max(count, importedActionUsageCountRange.lowerBound),
                                importedActionUsageCountRange.upperBound)
            let combined = min((merged[safeName] ?? 0) + safeCount,
                               importedActionUsageCountRange.upperBound)
            merged[safeName] = combined
        }
        let ranked = merged.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }.prefix(importedActionUsageLimit)
        return Dictionary(uniqueKeysWithValues: ranked.map { ($0.key, $0.value) })
    }

    static func sanitizedPrompt(_ value: String?,
                                fallback: String,
                                allowEmpty: Bool = false,
                                maxLength: Int = importedPromptLimit,
                                migrateOldTranslateDefault: Bool = false) -> String {
        var resolved = value ?? fallback
        if migrateOldTranslateDefault && resolved == oldDefaultTranslatePrompt {
            resolved = defaultTranslatePrompt
        }
        if resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return allowEmpty ? "" : fallback
        }
        return limitedImportedString(resolved,
                                     maxLength: maxLength,
                                     fallback: allowEmpty ? "" : fallback)
    }

    private static func uniqueImportedID(_ candidate: String, seenIDs: inout Set<String>) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let proposed = trimmed.isEmpty ? UUID().uuidString : trimmed
        if seenIDs.insert(proposed).inserted {
            return proposed
        }
        let replacement = UUID().uuidString
        seenIDs.insert(replacement)
        return replacement
    }

    private static func limitedImportedString(_ value: String,
                                              maxLength: Int,
                                              fallback: String) -> String {
        let resolved = value.isEmpty ? fallback : value
        guard resolved.count > maxLength else { return resolved }
        return String(resolved.prefix(maxLength))
    }

    private static func sanitizedOptionalImportedString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sanitizedActionModelOverride(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let limited = limitedImportedString(trimmed,
                                            maxLength: importedModelNameLimit,
                                            fallback: "")
        return limited.isEmpty ? nil : limited
    }

    static func sanitizedActiveModelName(_ value: String) -> String {
        limitedImportedString(value.trimmingCharacters(in: .whitespacesAndNewlines),
                              maxLength: importedModelNameLimit,
                              fallback: "")
    }

    private static func providerIDAfterProviderSanitization(originalProviders: [AIProvider],
                                                            sanitizedProviders: [AIProvider],
                                                            providerID: String,
                                                            modelName: String?) -> String {
        let requestedID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedID.isEmpty else { return "" }
        let requestedModel = sanitizedActiveModelName(modelName ?? "")
        let pairs = zip(Array(originalProviders.prefix(sanitizedProviders.count)), sanitizedProviders)
            .filter { original, _ in
                original.id.trimmingCharacters(in: .whitespacesAndNewlines) == requestedID
            }
        guard !pairs.isEmpty else { return requestedID }
        if !requestedModel.isEmpty,
           let match = pairs.first(where: { _, sanitized in
               sanitized.enabledModelNames.contains(requestedModel)
           }) {
            return match.1.id
        }
        return pairs[0].1.id
    }

    private func historyPayload(source: String,
                                output: String,
                                tags: [String],
                                contentStorage: HistoryContentStorage) -> (source: String, output: String, tags: [String]) {
        switch contentStorage {
        case .full:
            let sourcePayload = Self.limitedHistoryText(source,
                                                        maxLength: Self.historySourceCharacterLimit)
            let outputPayload = Self.limitedHistoryText(output,
                                                        maxLength: Self.historyOutputCharacterLimit)
            var appendedTags: [String] = []
            if sourcePayload.wasTruncated {
                appendedTags.append(PrivacyHistoryTag.sourceTruncated)
            }
            if outputPayload.wasTruncated {
                appendedTags.append(PrivacyHistoryTag.outputTruncated)
            }
            return (sourcePayload.text, outputPayload.text, Self.historyTags(tags, appending: appendedTags))
        case .metadataOnly:
            return ("", "", Self.historyTags(tags, appending: [PrivacyHistoryTag.metadataOnly]))
        }
    }

    private static func limitedHistoryText(_ text: String,
                                           maxLength: Int) -> (text: String, wasTruncated: Bool) {
        guard text.count > maxLength else {
            return (text, false)
        }
        let marker = "\n\n[SnapAI: 历史记录已截断, 原始字符数 \(text.count)]"
        let visibleLimit = max(0, maxLength - marker.count)
        return (String(text.prefix(visibleLimit)) + marker, true)
    }

    private static func historyTags(_ tags: [String], appending appendedTags: [String] = []) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let requiredTags = normalizedHistoryTags(appendedTags)
        let userTagLimit = max(0, historyTagLimit - requiredTags.count)
        for value in normalizedHistoryTags(tags) where result.count < userTagLimit {
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        for value in requiredTags where result.count < historyTagLimit {
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static func normalizedHistoryTags(_ tags: [String]) -> [String] {
        tags.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let limited = limitedImportedString(normalized,
                                                maxLength: historyTagCharacterLimit,
                                                fallback: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return limited.isEmpty ? nil : limited
        }
    }

    private static func historyTags(_ tags: [String], appending tag: String) -> [String] {
        historyTags(tags, appending: [tag])
    }
}

/// 键码 → 名称 的最小映射(用于显示快捷键)
enum KeyCodeMap {
    static func name(for keyCode: UInt32) -> String {
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋",
            kVK_Delete: "Delete", kVK_ForwardDelete: "⌦"
        ]
        return map[Int(keyCode)] ?? "Key\(keyCode)"
    }
}
