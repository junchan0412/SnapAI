import SwiftUI

struct GeneralSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissionState: PermissionState
    @ObservedObject var ui: AISettingsUI
    let iCloudSyncStatusText: String
    let commit: () -> Void
    let applyCommit: (SettingsCommitPolicy) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                WorkModeSettingsSection(settings: settings) {
                    commit()
                }
                launchAndDisplaySection
                captureSection
                contextProfilesSection
                privacySection
                syncAndAnimationSection
                ConfigMigrationSettingsSection(settings: settings, commit: commit)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var launchAndDisplaySection: some View {
        settingsSection("启动与显示") {
            settingsToggleRow(
                title: "开机启动",
                description: "登录系统时自动在菜单栏常驻。",
                isOn: Binding(
                    get: { permissionState.launchAtLogin },
                    set: { permissionState.setLaunchAtLogin($0) }
                )
            )
            compactDivider
            settingsToggleRow(
                title: "Dock 图标",
                description: "关闭后仅保留菜单栏图标；开启时可从 Dock 打开设置。",
                isOn: Binding(
                    get: { settings.showDockIcon },
                    set: { settings.showDockIcon = $0; commit() }
                )
            )
            compactDivider
            resultPanelDismissRow
        }
    }

    private var resultPanelDismissRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("结果窗口失焦行为")
                    .font(.callout.weight(.medium))
                Text(settings.resultPanelDismissMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Picker("", selection: $settings.resultPanelDismissMode) {
                ForEach(ResultPanelDismissMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .controlSize(.small)
            .onChange(of: settings.resultPanelDismissMode) { commit() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captureSection: some View {
        settingsSection("取词") {
            settingsToggleRow(
                title: "优先辅助功能取词",
                description: "更无感地读取当前选中内容；关闭后统一通过模拟 Command-C 取词。",
                isOn: Binding(
                    get: { settings.useAXFirst },
                    set: { settings.useAXFirst = $0; commit() }
                )
            )
        }
    }

    private var contextProfilesSection: some View {
        ContextProfileSettingsSection(settings: settings,
                                      ui: ui,
                                      commit: commit,
                                      applyCommit: applyCommit)
    }

    private var privacySection: some View {
        PrivacySettingsSection(settings: settings,
                               ui: ui,
                               commit: commit,
                               applyCommit: applyCommit)
    }

    private var syncAndAnimationSection: some View {
        settingsSection("同步与动效") {
            settingsToggleRow(
                title: "iCloud 配置同步",
                description: "同步供应商配置、动作和快捷键，不包含 API Key。\(iCloudSyncStatusText)",
                isOn: Binding(
                    get: { settings.iCloudSyncEnabled },
                    set: { enabled in
                        settings.iCloudSyncEnabled = enabled
                        commit()
                        if enabled { iCloudSync.shared.upload(settings) }
                    }
                )
            )
            compactDivider
            typewriterSpeedRow
        }
    }

    private var typewriterSpeedRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("打字机动画")
                    .font(.callout.weight(.medium))
                Text("控制 AI 结果逐字显示速度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Picker("", selection: $settings.typewriterSpeed) {
                ForEach(TypewriterSpeed.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
            .controlSize(.small)
            .onChange(of: settings.typewriterSpeed) { commit() }
        }
    }

    private func settingsSection<Content: View>(_ title: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .snapAISurface(padding: 9, fillOpacity: SnapAIUI.quietFillOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsToggleRow(title: String,
                                   description: String,
                                   isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactDivider: some View {
        Divider()
            .opacity(0.55)
    }
}
