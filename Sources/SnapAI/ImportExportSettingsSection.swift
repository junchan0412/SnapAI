import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConfigMigrationSettingsSection: View {
    @ObservedObject var settings: AppSettings
    let commit: () -> Void
    @State private var pendingImportedConfig: AppSettings?
    @State private var configNotice: ConfigNotice?

    private func flashNotice(_ message: String, tone: ConfigNotice.Tone) {
        configNotice = ConfigNotice(message: message, tone: tone)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { configNotice = nil }
    }

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
        .confirmationDialog(
            "导入配置将覆盖当前设置",
            isPresented: Binding(get: { pendingImportedConfig != nil },
                                 set: { if !$0 { pendingImportedConfig = nil } }),
            titleVisibility: .visible,
            presenting: pendingImportedConfig
        ) { _ in
            Button("覆盖导入", role: .destructive) { applyImportedConfig() }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("将用所选文件中的供应商、动作、快捷键、脱敏规则等覆盖当前配置，此操作不可撤销。建议先导出当前配置备份。")
        }
        .overlay(alignment: .bottom) {
            if let notice = configNotice {
                Label(notice.message, systemImage: notice.icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(notice.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity)
                    .accessibilityLabel(notice.message)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: configNotice)
    }

    private func exportConfig() {
        guard let exportData = settings.exportConfigurationData() else {
            flashNotice("生成配置失败", tone: .error)
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SnapAI-config.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try exportData.write(to: url, options: .atomic)
            flashNotice("已导出到 \(url.lastPathComponent)", tone: .success)
        } catch {
            flashNotice("写入文件失败", tone: .error)
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            flashNotice("读取文件失败", tone: .error)
            return
        }
        guard let imported = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            flashNotice("文件格式无法识别", tone: .error)
            return
        }
        // 解析成功后再让用户确认覆盖,避免无确认直接覆盖现有配置。
        pendingImportedConfig = imported
    }

    private func applyImportedConfig() {
        guard let imported = pendingImportedConfig else { return }
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
        pendingImportedConfig = nil
        flashNotice("配置已导入", tone: .success)
    }
}

private struct ConfigNotice: Equatable {
    let message: String
    let tone: Tone

    enum Tone {
        case success, error
        var color: Color {
            switch self {
            case .success: return SnapAIUI.StatusColor.success
            case .error: return SnapAIUI.StatusColor.error
            }
        }
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        }
    }

    static func == (lhs: ConfigNotice, rhs: ConfigNotice) -> Bool {
        lhs.message == rhs.message
    }
}
