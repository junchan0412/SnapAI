import Foundation

package enum AutomationRouter {
    package static func command(from rawURL: String) -> AutomationURLCommand? {
        guard let url = URL(string: rawURL) else { return nil }
        return AutomationURLCommand.parse(url)
    }

    package static func settingsSection(for raw: String?,
                                fallback: SettingsSection) -> SettingsSection {
        AutomationSettingsSectionSelection.resolve(raw, fallback: fallback)
    }
}
