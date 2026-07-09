import Foundation
import SnapAILogic

extension SettingsToggleCommand {
    func isEnabled(in settings: AppSettings) -> Bool {
        isEnabled(in: state(from: settings))
    }

    func setEnabled(_ enabled: Bool, in settings: AppSettings) {
        switch self {
        case .privacyPreview:
            settings.privacyPreviewEnabled = enabled
        case .redaction:
            settings.redactionEnabled = enabled
        case .historyMetadataOnly:
            settings.historyContentStorage = enabled ? .metadataOnly : .full
        case .autoRoute:
            settings.autoRouteEnabled = enabled
        case .fallback:
            settings.fallbackEnabled = enabled
        }
    }

    private func state(from settings: AppSettings) -> SettingsToggleCommandState {
        SettingsToggleCommandState(
            privacyPreviewEnabled: settings.privacyPreviewEnabled,
            redactionEnabled: settings.redactionEnabled,
            historyMetadataOnly: settings.historyContentStorage == .metadataOnly,
            autoRouteEnabled: settings.autoRouteEnabled,
            fallbackEnabled: settings.fallbackEnabled
        )
    }
}
