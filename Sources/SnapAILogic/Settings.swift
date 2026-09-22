import Foundation
import Combine

/// 结果浮窗失焦时的关闭策略
package enum ResultPanelDismissMode: String, CaseIterable, Codable {
    case autoDismiss      // 点外部即关(旧行为)
    case keepAfterResult  // 生成完成后保持,仅 Esc/X/写回关闭
    case alwaysKeep       // 始终保持,仅 Esc/X/写回关闭

    package var title: String {
        switch self {
        case .autoDismiss: return "自动关闭"
        case .keepAfterResult: return "生成后保持"
        case .alwaysKeep: return "始终保持"
        }
    }
    package var description: String {
        switch self {
        case .autoDismiss: return "点击结果窗口外部即关闭(需手动固定才能保留)。"
        case .keepAfterResult: return "结果生成完成后点击外部不关闭;生成中点击外部也不关闭。"
        case .alwaysKeep: return "始终保留,仅按 Esc、点关闭按钮或写回原文时关闭。"
        }
    }
}

/// 全局设置,持久化到 UserDefaults
package final class AppSettings: ObservableObject, Codable {
    package static let shared = AppSettings.load()
    package static let currentSchemaVersion = 2
    package static let defaultPanelWidth: Double = 600
    package static let defaultPanelHeight: Double = 640
    package static let importedPanelWidthRange: ClosedRange<Double> = 320...1_400
    package static let importedPanelHeightRange: ClosedRange<Double> = 200...1_000
    package static let importedHistoryLimitRange = 0...500
    package static let importedRedactionRuleLimit = 80
    package static let importedRedactionNameLimit = 80
    package static let importedRedactionPatternLimit = PrivacyFilter.maxPatternLength
    package static let importedRedactionReplacementLimit = PrivacyFilter.maxReplacementLength
    package static let importedContextProfileLimit = 24
    package static let importedContextNameLimit = 80
    package static let importedContextContentLimit = 40_000
    package static let importedProviderLimit = 12
    package static let importedProviderNameLimit = 80
    package static let importedProviderBaseURLLimit = 500
    package static let importedModelLimit = 200
    package static let importedModelNameLimit = 160
    package static let importedPromptLimit = AIAction.maxPromptLength
    package static let importedSystemPromptLimit = AIAction.maxPromptLength
    package static let importedMaxTokensRange = 1...200_000
    package static let importedRequestTimeoutRange: ClosedRange<Double> = 5...300
    package static let importedActionLimit = 80
    package static let importedActionUsageLimit = 200
    package static let importedActionUsageCountRange = 1...1_000_000
    package static let historySourceCharacterLimit = 20_000
    package static let historyOutputCharacterLimit = 40_000
    package static let historyTagLimit = 24
    package static let historyTagCharacterLimit = 48
    package static let importedSavedHistoryFilterLimit = 24
    package static let importedSavedHistoryFilterNameLimit = 80
    package static let importedSavedHistoryFilterQueryLimit = 240
    package static let defaultAskPrompt = "请简洁、准确地回答关于以下内容的问题或解释它:\n\n{{text}}"
    package static let oldDefaultTranslatePrompt = "请把下面的文字翻译成中文;如果它本身就是中文,则翻译成英文。只输出翻译结果,不要解释:\n\n{{text}}"
    package static let defaultTranslatePrompt = "请将下面的文字在中文和英文之间互译:如果原文是中文,翻译成自然流畅的英文;如果原文是英文或其他语言,翻译成简体中文。只输出翻译结果,不要解释:\n\n{{text}}"
    package static let defaultSystemPrompt = "你是一个简洁高效的助手,直接给出答案,避免冗余的客套话。"

    // AI 接入配置:多供应商
    @Published package var providers: [AIProvider] = []
    @Published package var activeProviderID: String = ""   // 当前激活的供应商 id
    @Published package var activeModel: String = ""        // 当前激活的模型名
    @Published package var temperature: Double = 0.3
    @Published package var settingsSchemaVersion: Int = AppSettings.currentSchemaVersion

    // 快捷键(旧:仅保留用于迁移与「快捷输入面板」)
    @Published package var askHotKey: HotKeyCombo = .askDefault
    @Published package var translateHotKey: HotKeyCombo = .translateDefault
    /// 快捷输入面板(不依赖选中文字)的全局快捷键
    @Published package var quickPanelHotKey: HotKeyCombo = .quickPanelDefault

    // 自定义动作(提问/翻译/润色/总结/解释代码…)
    @Published package var actions: [AIAction] = AIAction.defaults()

    // Prompt 模板,{{text}} 会被替换为选中文字(systemPrompt 仍全局生效)
    @Published package var askPrompt: String = AppSettings.defaultAskPrompt
    @Published package var translatePrompt: String = AppSettings.defaultTranslatePrompt
    @Published package var systemPrompt: String = AppSettings.defaultSystemPrompt

    // 行为
    @Published package var useAXFirst: Bool = true   // 优先用辅助功能取词
    @Published package var showDockIcon: Bool = true // 在 Dock 显示图标(可点击打开设置)
    @Published package var typewriterSpeed: TypewriterSpeed = .normal // 打字机动画速度
    @Published package var autoRouteEnabled: Bool = false
    @Published package var fallbackEnabled: Bool = true
    @Published package var routingPreference: AIRoutingPreference = .balanced
    @Published package var workModePreset: WorkModePreset = .standard
    @Published package var privacyPreviewEnabled: Bool = false
    @Published package var redactionEnabled: Bool = false
    @Published package var redactionRules: [PrivacyRedactionRule] = PrivacyRedactionRule.defaults()
    @Published package var contextProfiles: [ContextProfile] = ContextProfile.defaults()
    @Published package var activeContextProfileID: String = ""

    // 历史 / 引导 / 窗口尺寸
    @Published package var history: [HistoryEntry] = [] {
        didSet { historyNeedsValidation = true }
    }
    @Published package var historyLimit: Int = 50 {
        didSet {
            guard historyLimit != oldValue else { return }
            historyNeedsValidation = true
            historyLimitNeedsPersistence = true
        }
    }
    @Published package var historyContentStorage: HistoryContentStorage = .full
    @Published package var savedHistoryFilters: [SavedHistoryFilter] = []
    @Published package var onboardingDone: Bool = false
    @Published package var panelWidth: Double = AppSettings.defaultPanelWidth
    @Published package var panelHeight: Double = AppSettings.defaultPanelHeight
    // 结果浮窗失焦行为(#bug1)
    @Published package var resultPanelDismissMode: ResultPanelDismissMode = .keepAfterResult
    // 统计(#11) 动作使用次数,key = 动作名
    @Published package var actionUsageCounts: [String: Int] = [:]
    // iCloud 同步开关(#9)
    @Published package var iCloudSyncEnabled: Bool = false
    @Published package var iCloudDeviceID: String = AppSettings.stableICloudDeviceID()
    @Published package var iCloudRevision: Int = 0
    @Published package var iCloudUpdatedAt: Date? = nil
    @Published package var iCloudLastSyncAt: Date? = nil
    @Published package var iCloudLastSyncStatus: String = "未同步"
    @Published package var iCloudLastRemoteDeviceID: String = ""
    @Published package var iCloudHasLocalChanges: Bool = false

    // MARK: - 当前激活配置(兼容旧的扁平访问方式,供 AIClient / ModelLoader 使用)

    /// 当前激活的供应商。只返回已启用供应商,避免禁用项继续参与请求。
    package var activeProvider: AIProvider? {
        providers.first(where: { $0.id == activeProviderID && $0.isEnabled })
            ?? providers.first(where: { $0.isEnabled })
    }

    package var apiProtocol: APIProtocol { activeProvider?.apiProtocol ?? .openAI }
    package var baseURL: String { activeProvider?.baseURL ?? "" }
    /// 粘贴 API Key 时常带入前后空格/换行,Anthropic 服务端不忽略空格(直接 401 invalid)。
    /// 在此统一 trim,测试连接/拉取模型/流式请求与就绪检查全部受益;存储层仍保留原文。
    package var apiKey: String {
        (activeProvider?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    package var model: String {
        guard let provider = activeProvider else { return "" }
        let enabledModels = provider.enabledModelNames
        if enabledModels.contains(activeModel) {
            return activeModel
        }
        return enabledModels.first ?? ""
    }

    package var modelSelectionTitle: String {
        model.isEmpty ? "选择模型" : model
    }

    /// 选中某个供应商的某个模型为当前激活
    package func activate(providerID: String, model: String, recordManualPreference: Bool = false) {
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
    package func normalizeActive() {
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

    /// 所有「启用供应商 → 启用模型」的扁平条目,用于菜单栏快速切换
    package var switchableEntries: [(provider: AIProvider, model: String)] {
        var result: [(AIProvider, String)] = []
        for p in providers where p.isEnabled {
            for m in p.enabledModelNames {
                result.append((p, m))
            }
        }
        return result
    }

    /// 启用的动作(用于菜单/快捷键注册)
    package var enabledActions: [AIAction] { actions.filter { $0.isEnabled } }

    package enum CodingKeys: String, CodingKey {
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
        case resultPanelDismissMode
        case actionUsageCounts, iCloudSyncEnabled
        case iCloudDeviceID, iCloudRevision, iCloudUpdatedAt, iCloudLastSyncAt, iCloudLastSyncStatus, iCloudLastRemoteDeviceID
        case iCloudHasLocalChanges
        // 旧:单配置(仅用于迁移,不再写出)
        case apiProtocol, baseURL, apiKey, model
    }

    package init() {
        providers = [AIProvider.preset(.openAI)]
        if let first = providers.first {
            activeProviderID = first.id
            activeModel = first.enabledModelNames.first ?? ""
        }
    }

    package init(from decoder: Decoder) throws {
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
        resultPanelDismissMode = (try? c.decode(ResultPanelDismissMode.self, forKey: .resultPanelDismissMode)) ?? .keepAfterResult
        let decodedActionUsageCounts = (try? c.decode([String: Int].self, forKey: .actionUsageCounts)) ?? [:]
        actionUsageCounts = Self.sanitizedStoredActionUsageCounts(decodedActionUsageCounts)
        if actionUsageCounts != decodedActionUsageCounts {
            needsPostLoadSave = true
        }
        iCloudSyncEnabled = (try? c.decode(Bool.self, forKey: .iCloudSyncEnabled)) ?? false
        iCloudDeviceID = Self.sanitizedICloudDeviceID(try? c.decode(String.self, forKey: .iCloudDeviceID))
        iCloudRevision = max(0, (try? c.decode(Int.self, forKey: .iCloudRevision)) ?? 0)
        iCloudUpdatedAt = try? c.decode(Date.self, forKey: .iCloudUpdatedAt)
        iCloudLastSyncAt = try? c.decode(Date.self, forKey: .iCloudLastSyncAt)
        iCloudLastSyncStatus = Self.limitedImportedString(
            (try? c.decode(String.self, forKey: .iCloudLastSyncStatus)) ?? "未同步",
            maxLength: 160,
            fallback: "未同步"
        )
        iCloudLastRemoteDeviceID = Self.limitedImportedString(
            (try? c.decode(String.self, forKey: .iCloudLastRemoteDeviceID)) ?? "",
            maxLength: 80,
            fallback: ""
        )
        iCloudHasLocalChanges = (try? c.decode(Bool.self, forKey: .iCloudHasLocalChanges)) ?? false

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

    package func encode(to encoder: Encoder) throws {
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
        try c.encode(resultPanelDismissMode, forKey: .resultPanelDismissMode)
        try c.encode(actionUsageCounts, forKey: .actionUsageCounts)
        try c.encode(iCloudSyncEnabled, forKey: .iCloudSyncEnabled)
        try c.encode(iCloudDeviceID, forKey: .iCloudDeviceID)
        try c.encode(iCloudRevision, forKey: .iCloudRevision)
        try c.encodeIfPresent(iCloudUpdatedAt, forKey: .iCloudUpdatedAt)
        try c.encodeIfPresent(iCloudLastSyncAt, forKey: .iCloudLastSyncAt)
        try c.encode(iCloudLastSyncStatus, forKey: .iCloudLastSyncStatus)
        try c.encode(iCloudLastRemoteDeviceID, forKey: .iCloudLastRemoteDeviceID)
        try c.encode(iCloudHasLocalChanges, forKey: .iCloudHasLocalChanges)
    }

    package static let storeKey = "SnapAI.settings.v1"

    /// 已写入本地加密密钥存储的 Key 快照,避免每次 save() 都重复写(打字时 commit 很频繁)
    package var secretStoreCache: [String: String] = [:]
    package var secretStoreStatus: String = "not-checked"
    package var needsPostLoadSave = false
    package var historyNeedsValidation = true
    package var historyLimitNeedsPersistence = false
    package var historyNeedsMigrationRetry = false
    package var persistenceDefaults: UserDefaults = .standard
    package var persistenceHistoryStore: HistoryStore = .shared
    package var lastSavedSettingsData: Data?

    package static let iCloudDeviceIDDefaultsKey = "SnapAI.iCloud.deviceID"

    package static func stableICloudDeviceID(defaults: UserDefaults = .standard) -> String {
        if let stored = defaults.string(forKey: iCloudDeviceIDDefaultsKey),
           isValidICloudDeviceID(stored) {
            return stored
        }
        let value = UUID().uuidString
        defaults.set(value, forKey: iCloudDeviceIDDefaultsKey)
        return value
    }

    package static func sanitizedICloudDeviceID(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return isValidICloudDeviceID(trimmed) ? trimmed : stableICloudDeviceID()
    }

    private static func isValidICloudDeviceID(_ value: String) -> Bool {
        guard value.count >= 8, value.count <= 80 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    package func applyMigrations(from version: Int) {
        guard version < Self.currentSchemaVersion else { return }
        if version < 2 {
            applyMissingDefaultHotKeys()
        }
        settingsSchemaVersion = Self.currentSchemaVersion
        needsPostLoadSave = true
    }

    package func applyMissingDefaultHotKeys() {
        for idx in actions.indices {
            guard actions[idx].hotKey == nil,
                  let hk = AIAction.defaultHotKeysByName[actions[idx].name] else { continue }
            actions[idx].hotKey = hk
        }
    }

    package func restoreDefaultHotKeys() {
        quickPanelHotKey = .quickPanelDefault
        var restoredDefaultNames = Set<String>()
        var reservedCombos = Set<HotKeyCombo>([quickPanelHotKey])

        for idx in actions.indices {
            let name = actions[idx].name
            guard let defaultHotKey = AIAction.defaultHotKeysByName[name] else { continue }
            if restoredDefaultNames.insert(name).inserted {
                actions[idx].hotKey = defaultHotKey
                reservedCombos.insert(defaultHotKey)
            } else if actions[idx].hotKey == defaultHotKey {
                actions[idx].hotKey = nil
            }
        }

        for idx in actions.indices {
            let name = actions[idx].name
            guard !AIAction.defaultActionNames.contains(name),
                  let hotKey = actions[idx].hotKey,
                  reservedCombos.contains(hotKey) else {
                continue
            }
            actions[idx].hotKey = nil
        }
    }



}
