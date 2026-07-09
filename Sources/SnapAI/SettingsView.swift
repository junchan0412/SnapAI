import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var navigation: SettingsNavigationModel
    var onChange: () -> Void   // 设置变更后回调(用于重注册快捷键 + 保存)
    @ObservedObject var pinState: SettingsWindowPinState
    var onPinChange: (Bool) -> Void

    @StateObject private var perm = PermissionState()
    @StateObject private var modelLoader = ModelLoader()
    @StateObject private var ui = AISettingsUI()
    @StateObject private var tester = ConnectionTester()
    let aiLabelWidth: CGFloat = 76
    private var isPinned: Bool { pinState.isPinned }
    private var iCloudSyncStatusText: String {
        guard settings.iCloudSyncEnabled else { return "" }
        let status = settings.iCloudLastSyncStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        let revision = max(0, settings.iCloudRevision)
        let base = status.isEmpty ? "状态: 未同步" : "状态: \(status)"
        return " \(base), revision \(revision)。"
    }

    var body: some View {
        NavigationSplitView {
            settingsSidebar
        } detail: {
            VStack(spacing: 0) {
                settingsHeader
                Divider()
                settingsContentSurface
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, idealWidth: 840, minHeight: 560, idealHeight: 620)
        .onDisappear {
            flushDeferredSave()
        }
    }

    private var settingsSidebar: some View {
        List(selection: Binding<SettingsSection?>(
            get: { navigation.selectedSection },
            set: { selected in
                guard let selected else { return }
                withAnimation(.easeInOut(duration: 0.16)) {
                    navigation.select(selected)
                }
            }
        )) {
            Section("设置") {
                ForEach(SettingsSection.allCases) { section in
                    SettingsSidebarRow(section: section)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 164, ideal: 188, max: 230)
    }

    private var settingsHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: navigation.selectedSection.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(navigation.selectedSection.title)
                    .font(.title3.weight(.semibold))
                Text(navigation.selectedSection.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            pinButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private var pinButton: some View {
        Button {
            let newValue = !pinState.isPinned
            withAnimation(.easeInOut(duration: 0.16)) {
                pinState.isPinned = newValue
            }
            onPinChange(newValue)
        } label: {
            Image(systemName: SettingsWindowPinCommand.statusSystemImage(isPinned: isPinned))
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .scaleEffect(isPinned ? 1.04 : 0.96)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isPinned ? Color.accentColor : .secondary)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isPinned ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isPinned ? Color.accentColor.opacity(0.38) : Color.primary.opacity(0.1), lineWidth: 1)
        }
        .help(isPinned ? "已置顶:点击取消置顶" : "未置顶:点击置顶设置窗口")
        .accessibilityLabel(isPinned ? "设置窗口已置顶" : "设置窗口未置顶")
        .accessibilityValue(SettingsWindowPinCommand.accessibilityValue(isPinned: isPinned))
    }

    private var settingsContentSurface: some View {
        ZStack {
            selectedSectionContent
                .id(navigation.selectedSection.id)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.14), value: navigation.selectedSection)
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch navigation.selectedSection {
        case .ai:
            aiTab
        case .actions:
            actionsTab
        case .history:
            historyTab
        case .general:
            generalTab
        case .permission:
            permissionTab
        }
    }

    private var aiTab: some View {
        ProviderSettingsSection(settings: settings,
                                ui: ui,
                                modelLoader: modelLoader,
                                tester: tester,
                                onChange: onChange,
                                commit: commit,
                                applyCommit: applyCommit)
    }

    private var actionsTab: some View {
        ActionSettingsSection(settings: settings,
                              navigation: navigation,
                              ui: ui,
                              commit: commit,
                              applyCommit: applyCommit)
    }

    // MARK: - 历史

    private var historyTab: some View {
        HistorySettingsSection(settings: settings, commit: commit)
    }

    // MARK: - 通用

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                WorkModeSettingsSection(settings: settings) {
                    commit()
                }

                settingsSection("启动与显示") {
                    settingsToggleRow(
                        title: "开机启动",
                        description: "登录系统时自动在菜单栏常驻。",
                        isOn: Binding(
                            get: { perm.launchAtLogin },
                            set: { perm.setLaunchAtLogin($0) }
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
                }

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

                contextProfilesSection
                privacySection

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

                ConfigMigrationSettingsSection(settings: settings, commit: commit)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var privacySection: some View {
        PrivacySettingsSection(settings: settings,
                               ui: ui,
                               commit: commit,
                               applyCommit: applyCommit)
    }

    private var contextProfilesSection: some View {
        ContextProfileSettingsSection(settings: settings,
                                      ui: ui,
                                      commit: commit,
                                      applyCommit: applyCommit)
    }

    // MARK: - 权限

    private var permissionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settingsSection("辅助功能") {
                    HStack(spacing: 10) {
                        Image(systemName: perm.axGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(perm.axGranted ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(perm.axGranted ? "已授予辅助功能权限" : "未授予辅助功能权限")
                                .font(.callout.weight(.medium))
                            Text("SnapAI 需要该权限来读取选中文字并模拟复制按键。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    compactDivider
                    HStack(spacing: 8) {
                        Button("打开系统设置") {
                            NSWorkspace.shared.open(SystemPrivacySettings.accessibilityURL)
                        }
                        Button("重新检测") {
                            perm.refresh(prompt: true)
                        }
                        Spacer()
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func commit() {
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
        onChange()
    }

    private func applyCommit(_ policy: SettingsCommitPolicy) {
        switch policy {
        case .fullReload:
            commit()
        case .saveOnly:
            settings.save()
            iCloudSync.shared.scheduleUpload(settings)
        case .deferredSave:
            scheduleDeferredSave()
        }
    }

    private func scheduleDeferredSave() {
        ui.deferredSaveTask?.cancel()
        ui.deferredSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                settings.save()
                iCloudSync.shared.scheduleUpload(settings)
                ui.deferredSaveTask = nil
            }
        }
    }

    private func flushDeferredSave() {
        ui.deferredSaveTask?.cancel()
        ui.deferredSaveTask = nil
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
    }
}
