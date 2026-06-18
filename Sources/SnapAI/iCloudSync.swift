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

private struct CloudSettingsPayload: Codable {
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

    init(settings: AppSettings) {
        providers = settings.providers
        activeProviderID = settings.activeProviderID
        activeModel = settings.activeModel
        temperature = settings.temperature
        askHotKey = settings.askHotKey
        translateHotKey = settings.translateHotKey
        quickPanelHotKey = settings.quickPanelHotKey
        actions = settings.actions
        askPrompt = settings.askPrompt
        translatePrompt = settings.translatePrompt
        systemPrompt = settings.systemPrompt
        useAXFirst = settings.useAXFirst
        showDockIcon = settings.showDockIcon
        typewriterSpeed = settings.typewriterSpeed
    }

    func apply(to settings: AppSettings) {
        var mergedProviders = providers
        for i in mergedProviders.indices where mergedProviders[i].apiKey.isEmpty {
            mergedProviders[i].apiKey = Keychain.apiKey(for: mergedProviders[i].id)
        }

        settings.providers = mergedProviders
        settings.activeProviderID = activeProviderID
        settings.activeModel = activeModel
        settings.temperature = temperature
        settings.askHotKey = askHotKey
        settings.translateHotKey = translateHotKey
        settings.quickPanelHotKey = quickPanelHotKey
        settings.actions = actions
        settings.askPrompt = askPrompt
        settings.translatePrompt = translatePrompt
        settings.systemPrompt = systemPrompt
        settings.useAXFirst = useAXFirst
        settings.showDockIcon = showDockIcon
        settings.typewriterSpeed = typewriterSpeed
        settings.normalizeActive()
    }
}
