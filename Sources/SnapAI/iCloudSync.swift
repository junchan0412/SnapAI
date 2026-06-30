import Foundation

/// iCloud Key-Value Store 同步:只同步配置载荷,不包含历史记录、统计、窗口状态或 API Key。
final class iCloudSync {
    static let shared = iCloudSync()
    private let store = NSUbiquitousKeyValueStore.default
    private let key = "SnapAI.settings.icloud.v1"
    private var pendingUpload: DispatchWorkItem?

    private init() {}

    /// 把当前配置上传到 iCloud。API Key 由 AIProvider 的 Codable 排除,历史等运行数据由 CloudSettingsPayload 排除。
    func upload(_ settings: AppSettings) {
        guard settings.iCloudSyncEnabled else { return }
        let payload = CloudSettingsPayload(settings: settings)
        if let data = try? JSONEncoder().encode(payload) {
            store.set(data, forKey: key)
            store.synchronize()
        }
    }

    /// 设置页高频变更时防抖上传,避免每次键入都写 iCloud。
    func scheduleUpload(_ settings: AppSettings) {
        guard settings.iCloudSyncEnabled else {
            pendingUpload?.cancel()
            pendingUpload = nil
            return
        }
        pendingUpload?.cancel()
        let work = DispatchWorkItem { [settings] in
            Self.shared.upload(settings)
        }
        pendingUpload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    /// 启动或远端变化时拉取远端配置并合并到本地。返回是否应用了远端配置。
    @discardableResult
    func pullIfNeeded(into settings: AppSettings) -> Bool {
        guard settings.iCloudSyncEnabled else { return false }
        guard let data = store.data(forKey: key),
              let payload = decodePayload(data) else { return false }
        payload.apply(to: settings)
        settings.save()
        return true
    }

    /// 监听远端变化通知。应用远端配置后回调调用方刷新菜单、快捷键和 UI。
    func startListening(into settings: AppSettings, onApplied: @escaping () -> Void) {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            guard self?.pullIfNeeded(into: settings) == true else { return }
            onApplied()
        }
        store.synchronize()
    }

    private func decodePayload(_ data: Data) -> CloudSettingsPayload? {
        if let payload = try? JSONDecoder().decode(CloudSettingsPayload.self, from: data) {
            return payload
        }
        // 兼容旧版曾把整个 AppSettings 放进 iCloud 的格式,只抽取允许同步的配置字段。
        if let legacy = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return CloudSettingsPayload(settings: legacy)
        }
        return nil
    }
}

struct CloudSettingsPayload: Codable {
    var providers: [AIProvider]
    var activeProviderID: String
    var activeModel: String
    var temperature: Double
    var askHotKey: HotKeyCombo
    var translateHotKey: HotKeyCombo
    var quickPanelHotKey: HotKeyCombo
    var actions: [AIAction]
    var askPrompt: String
    var translatePrompt: String
    var systemPrompt: String
    var useAXFirst: Bool
    var showDockIcon: Bool
    var typewriterSpeed: TypewriterSpeed
    var autoRouteEnabled: Bool
    var fallbackEnabled: Bool
    var routingPreference: AIRoutingPreference
    var workModePreset: WorkModePreset
    var privacyPreviewEnabled: Bool
    var redactionEnabled: Bool
    var redactionRules: [PrivacyRedactionRule]
    var historyContentStorage: HistoryContentStorage
    var contextProfiles: [ContextProfile]
    var activeContextProfileID: String

    init(settings: AppSettings) {
        let providerConfig = AppSettings.importedProviderConfiguration(settings.providers,
                                                                       activeProviderID: settings.activeProviderID,
                                                                       activeModel: settings.activeModel) { _ in "" }
        providers = providerConfig.providers
        activeProviderID = providerConfig.activeProviderID
        activeModel = providerConfig.activeModel
        temperature = AppSettings.clampedTemperature(settings.temperature)
        askHotKey = settings.askHotKey
        translateHotKey = settings.translateHotKey
        quickPanelHotKey = settings.quickPanelHotKey
        actions = AppSettings.sanitizedImportedActions(settings.actions,
                                                       originalProviders: settings.providers,
                                                       sanitizedProviders: providers)
        askPrompt = AppSettings.sanitizedPrompt(settings.askPrompt,
                                                fallback: AppSettings.defaultAskPrompt)
        translatePrompt = AppSettings.sanitizedPrompt(settings.translatePrompt,
                                                      fallback: AppSettings.defaultTranslatePrompt,
                                                      migrateOldTranslateDefault: true)
        systemPrompt = AppSettings.sanitizedPrompt(settings.systemPrompt,
                                                   fallback: AppSettings.defaultSystemPrompt,
                                                   allowEmpty: true,
                                                   maxLength: AppSettings.importedSystemPromptLimit)
        useAXFirst = settings.useAXFirst
        showDockIcon = settings.showDockIcon
        typewriterSpeed = settings.typewriterSpeed
        autoRouteEnabled = settings.autoRouteEnabled
        fallbackEnabled = settings.fallbackEnabled
        routingPreference = settings.routingPreference
        workModePreset = settings.workModePreset
        privacyPreviewEnabled = settings.privacyPreviewEnabled
        redactionEnabled = settings.redactionEnabled
        redactionRules = AppSettings.sanitizedImportedRedactionRules(settings.redactionRules)
        historyContentStorage = settings.historyContentStorage
        let context = AppSettings.sanitizedImportedContextProfiles(settings.contextProfiles,
                                                                   activeID: settings.activeContextProfileID)
        contextProfiles = context.profiles
        activeContextProfileID = context.activeID
    }

    enum CodingKeys: String, CodingKey {
        case providers, activeProviderID, activeModel, temperature
        case askHotKey, translateHotKey, quickPanelHotKey
        case actions, askPrompt, translatePrompt, systemPrompt
        case useAXFirst, showDockIcon, typewriterSpeed
        case autoRouteEnabled, fallbackEnabled, routingPreference, workModePreset
        case privacyPreviewEnabled, redactionEnabled, redactionRules
        case historyContentStorage
        case contextProfiles, activeContextProfileID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedProviders = (try? c.decode([AIProvider].self, forKey: .providers)) ?? []
        let decodedActiveProviderID = (try? c.decode(String.self, forKey: .activeProviderID)) ?? ""
        let decodedActiveModel = (try? c.decode(String.self, forKey: .activeModel)) ?? ""
        let providerConfig = AppSettings.importedProviderConfiguration(decodedProviders,
                                                                       activeProviderID: decodedActiveProviderID,
                                                                       activeModel: decodedActiveModel)
        providers = providerConfig.providers
        activeProviderID = providerConfig.activeProviderID
        activeModel = providerConfig.activeModel
        temperature = AppSettings.clampedTemperature((try? c.decode(Double.self, forKey: .temperature)) ?? 0.3)
        askHotKey = (try? c.decode(HotKeyCombo.self, forKey: .askHotKey)) ?? .askDefault
        translateHotKey = (try? c.decode(HotKeyCombo.self, forKey: .translateHotKey)) ?? .translateDefault
        quickPanelHotKey = (try? c.decode(HotKeyCombo.self, forKey: .quickPanelHotKey)) ?? .quickPanelDefault
        actions = AppSettings.sanitizedImportedActions((try? c.decode([AIAction].self, forKey: .actions)) ?? AIAction.defaults(),
                                                       originalProviders: decodedProviders,
                                                       sanitizedProviders: providers)
        askPrompt = AppSettings.sanitizedPrompt(try? c.decode(String.self, forKey: .askPrompt),
                                                fallback: AppSettings.defaultAskPrompt)
        translatePrompt = AppSettings.sanitizedPrompt(try? c.decode(String.self, forKey: .translatePrompt),
                                                      fallback: AppSettings.defaultTranslatePrompt,
                                                      migrateOldTranslateDefault: true)
        systemPrompt = AppSettings.sanitizedPrompt(try? c.decode(String.self, forKey: .systemPrompt),
                                                   fallback: AppSettings.defaultSystemPrompt,
                                                   allowEmpty: true,
                                                   maxLength: AppSettings.importedSystemPromptLimit)
        useAXFirst = (try? c.decode(Bool.self, forKey: .useAXFirst)) ?? true
        showDockIcon = (try? c.decode(Bool.self, forKey: .showDockIcon)) ?? true
        typewriterSpeed = (try? c.decode(TypewriterSpeed.self, forKey: .typewriterSpeed)) ?? .normal
        autoRouteEnabled = (try? c.decode(Bool.self, forKey: .autoRouteEnabled)) ?? false
        fallbackEnabled = (try? c.decode(Bool.self, forKey: .fallbackEnabled)) ?? true
        routingPreference = (try? c.decode(AIRoutingPreference.self, forKey: .routingPreference)) ?? .balanced
        workModePreset = (try? c.decode(WorkModePreset.self, forKey: .workModePreset)) ?? .standard
        privacyPreviewEnabled = (try? c.decode(Bool.self, forKey: .privacyPreviewEnabled)) ?? false
        redactionEnabled = (try? c.decode(Bool.self, forKey: .redactionEnabled)) ?? false
        redactionRules = AppSettings.sanitizedImportedRedactionRules(
            (try? c.decode([PrivacyRedactionRule].self, forKey: .redactionRules)) ?? PrivacyRedactionRule.defaults()
        )
        historyContentStorage = (try? c.decode(HistoryContentStorage.self, forKey: .historyContentStorage)) ?? .full
        let decodedActiveContextProfileID = (try? c.decode(String.self, forKey: .activeContextProfileID)) ?? ""
        let context = AppSettings.sanitizedImportedContextProfiles(
            (try? c.decode([ContextProfile].self, forKey: .contextProfiles)) ?? ContextProfile.defaults(),
            activeID: decodedActiveContextProfileID
        )
        contextProfiles = context.profiles
        activeContextProfileID = context.activeID
    }

    func apply(to settings: AppSettings) {
        let providerConfig = AppSettings.importedProviderConfiguration(providers,
                                                                       activeProviderID: activeProviderID,
                                                                       activeModel: activeModel)
        settings.providers = providerConfig.providers
        settings.activeProviderID = providerConfig.activeProviderID
        settings.activeModel = providerConfig.activeModel
        settings.temperature = temperature
        settings.askHotKey = askHotKey
        settings.translateHotKey = translateHotKey
        settings.quickPanelHotKey = quickPanelHotKey
        settings.actions = AppSettings.sanitizedImportedActions(actions,
                                                                originalProviders: providers,
                                                                sanitizedProviders: settings.providers)
        settings.askPrompt = AppSettings.sanitizedPrompt(askPrompt,
                                                         fallback: AppSettings.defaultAskPrompt)
        settings.translatePrompt = AppSettings.sanitizedPrompt(translatePrompt,
                                                               fallback: AppSettings.defaultTranslatePrompt,
                                                               migrateOldTranslateDefault: true)
        settings.systemPrompt = AppSettings.sanitizedPrompt(systemPrompt,
                                                            fallback: AppSettings.defaultSystemPrompt,
                                                            allowEmpty: true,
                                                            maxLength: AppSettings.importedSystemPromptLimit)
        settings.useAXFirst = useAXFirst
        settings.showDockIcon = showDockIcon
        settings.typewriterSpeed = typewriterSpeed
        settings.autoRouteEnabled = autoRouteEnabled
        settings.fallbackEnabled = fallbackEnabled
        settings.routingPreference = routingPreference
        settings.workModePreset = workModePreset
        settings.privacyPreviewEnabled = privacyPreviewEnabled
        settings.redactionEnabled = redactionEnabled
        settings.redactionRules = redactionRules
        settings.historyContentStorage = historyContentStorage
        settings.contextProfiles = contextProfiles
        settings.activeContextProfileID = activeContextProfileID
        settings.normalizeActive()
    }
}
