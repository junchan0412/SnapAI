import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConfigMigrationSettingsSection: View {
    @ObservedObject var settings: AppSettings
    let commit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("配置迁移")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button("导出配置…") { exportConfig() }
                    Button("导入配置…") { importConfig() }
                    Spacer()
                }
                Text("导出为 JSON，包含供应商、动作、快捷键等；API Key 不会被导出。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .snapAISurface(padding: 9, fillOpacity: SnapAIUI.quietFillOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exportConfig() {
        guard let exportData = settings.exportConfigurationData() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SnapAI-config.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? exportData.write(to: url)
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let data = try? Data(contentsOf: url),
              let imported = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return
        }
        imported.normalizeImportedConfiguration()
        let providerConfig = AppSettings.importedProviderConfiguration(imported.providers,
                                                                       activeProviderID: imported.activeProviderID,
                                                                       activeModel: imported.activeModel)
        settings.providers = providerConfig.providers
        settings.activeProviderID = providerConfig.activeProviderID
        settings.activeModel = providerConfig.activeModel
        settings.temperature = imported.temperature
        settings.actions = AppSettings.sanitizedImportedActions(imported.actions,
                                                                originalProviders: imported.providers,
                                                                sanitizedProviders: settings.providers)
        settings.askHotKey = imported.askHotKey
        settings.translateHotKey = imported.translateHotKey
        settings.quickPanelHotKey = imported.quickPanelHotKey
        settings.askPrompt = imported.askPrompt
        settings.translatePrompt = imported.translatePrompt
        settings.systemPrompt = imported.systemPrompt
        settings.useAXFirst = imported.useAXFirst
        settings.showDockIcon = imported.showDockIcon
        settings.typewriterSpeed = imported.typewriterSpeed
        settings.autoRouteEnabled = imported.autoRouteEnabled
        settings.fallbackEnabled = imported.fallbackEnabled
        settings.routingPreference = imported.routingPreference
        settings.workModePreset = imported.workModePreset
        settings.privacyPreviewEnabled = imported.privacyPreviewEnabled
        settings.redactionEnabled = imported.redactionEnabled
        settings.redactionRules = imported.redactionRules
        settings.historyContentStorage = imported.historyContentStorage
        settings.savedHistoryFilters = imported.savedHistoryFilters
        settings.contextProfiles = imported.contextProfiles
        settings.activeContextProfileID = imported.activeContextProfileID
        settings.historyLimit = imported.historyLimit
        settings.normalizeActive()
        commit()
    }
}
