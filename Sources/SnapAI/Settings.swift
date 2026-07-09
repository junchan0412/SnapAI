import Foundation
import Combine

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
    @Published var iCloudDeviceID: String = AppSettings.stableICloudDeviceID()
    @Published var iCloudRevision: Int = 0
    @Published var iCloudUpdatedAt: Date? = nil
    @Published var iCloudLastSyncAt: Date? = nil
    @Published var iCloudLastSyncStatus: String = "未同步"
    @Published var iCloudLastRemoteDeviceID: String = ""
    @Published var iCloudHasLocalChanges: Bool = false

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
        case iCloudDeviceID, iCloudRevision, iCloudUpdatedAt, iCloudLastSyncAt, iCloudLastSyncStatus, iCloudLastRemoteDeviceID
        case iCloudHasLocalChanges
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
        try c.encode(iCloudDeviceID, forKey: .iCloudDeviceID)
        try c.encode(iCloudRevision, forKey: .iCloudRevision)
        try c.encodeIfPresent(iCloudUpdatedAt, forKey: .iCloudUpdatedAt)
        try c.encodeIfPresent(iCloudLastSyncAt, forKey: .iCloudLastSyncAt)
        try c.encode(iCloudLastSyncStatus, forKey: .iCloudLastSyncStatus)
        try c.encode(iCloudLastRemoteDeviceID, forKey: .iCloudLastRemoteDeviceID)
        try c.encode(iCloudHasLocalChanges, forKey: .iCloudHasLocalChanges)
    }

    static let storeKey = "SnapAI.settings.v1"

    /// 已写入本地加密密钥存储的 Key 快照,避免每次 save() 都重复写(打字时 commit 很频繁)
    var secretStoreCache: [String: String] = [:]
    var secretStoreStatus: String = "not-checked"
    var needsPostLoadSave = false

    static let iCloudDeviceIDDefaultsKey = "SnapAI.iCloud.deviceID"

    static func stableICloudDeviceID(defaults: UserDefaults = .standard) -> String {
        if let stored = defaults.string(forKey: iCloudDeviceIDDefaultsKey),
           isValidICloudDeviceID(stored) {
            return stored
        }
        let value = UUID().uuidString
        defaults.set(value, forKey: iCloudDeviceIDDefaultsKey)
        return value
    }

    static func sanitizedICloudDeviceID(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return isValidICloudDeviceID(trimmed) ? trimmed : stableICloudDeviceID()
    }

    private static func isValidICloudDeviceID(_ value: String) -> Bool {
        guard value.count >= 8, value.count <= 80 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    func applyMigrations(from version: Int) {
        guard version < Self.currentSchemaVersion else { return }
        if version < 2 {
            applyMissingDefaultHotKeys()
        }
        settingsSchemaVersion = Self.currentSchemaVersion
        needsPostLoadSave = true
    }

    func applyMissingDefaultHotKeys() {
        for idx in actions.indices {
            guard actions[idx].hotKey == nil,
                  let hk = AIAction.defaultHotKeysByName[actions[idx].name] else { continue }
            actions[idx].hotKey = hk
        }
    }

    func restoreDefaultHotKeys() {
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
