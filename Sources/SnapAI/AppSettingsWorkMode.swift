import Foundation

extension AppSettings {
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
}
