import SwiftUI
import SnapAILogic

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
    @State private var saveFailed = false
    @State private var pendingFullReload = false
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
            SettingsWorkspaceSidebar(
                selection: Binding(
                    get: { navigation.selectedSection },
                    set: { navigation.select($0) }
                ),
                providerName: settings.activeProvider?.name,
                modelName: settings.model,
                shortcut: settings.quickPanelHotKey.displayString
            )
        } detail: {
            VStack(spacing: 0) {
                settingsHeader
                settingsContentSurface
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SnapAIUI.Surface.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 840, idealWidth: 960, minHeight: 620, idealHeight: 720)
        .onDisappear {
            flushDeferredSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            flushDeferredSave()
        }
        .overlay(alignment: .bottom) {
            if saveFailed {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SnapAIUI.StatusColor.error)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("设置尚未保存")
                            .font(.callout.weight(.semibold))
                        Text("修改仍在当前应用中。请检查磁盘空间或文件权限后重试。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("重试保存") { persistSettings(reload: pendingFullReload) }
                        .buttonStyle(.bordered)
                }
                .padding(14)
                .frame(maxWidth: 620)
                .snapAIGlassCard(radius: 14)
                .padding(20)
            }
        }
    }

    private var settingsHeader: some View {
        HStack(alignment: .center, spacing: SnapAIUI.standardSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(navigation.selectedSection.title)
                    .font(SnapAIUI.Typography.windowTitle)
                Text(navigation.selectedSection.subtitle)
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            pinButton
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .snapAIChrome()
    }

    private var pinButton: some View {
        Button {
            let newValue = !pinState.isPinned
            pinState.isPinned = newValue
            onPinChange(newValue)
        } label: {
            Image(systemName: SettingsWindowPinCommand.statusSystemImage(isPinned: isPinned))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isPinned ? Color.accentColor : .secondary)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(SnapAIIconButtonStyle(circular: false))
        .foregroundStyle(isPinned ? Color.accentColor : .secondary)
        .background {
            RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous)
                .fill(isPinned ? SnapAIUI.Surface.selected : .clear)
        }
        .help(isPinned ? "已置顶:点击取消置顶" : "未置顶:点击置顶设置窗口")
        .accessibilityLabel(isPinned ? "设置窗口已置顶" : "设置窗口未置顶")
        .accessibilityValue(SettingsWindowPinCommand.accessibilityValue(isPinned: isPinned))
    }

    private var settingsContentSurface: some View {
        selectedSectionContent
            .frame(maxWidth: 920, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        GeneralSettingsSection(settings: settings,
                               permissionState: perm,
                               ui: ui,
                               iCloudSyncStatusText: iCloudSyncStatusText,
                               commit: commit,
                               applyCommit: applyCommit)
    }

    // MARK: - 权限

    private var permissionTab: some View {
        PermissionSettingsSection(permissionState: perm)
    }

    private func commit() {
        persistSettings(reload: true)
    }

    private func persistSettings(reload: Bool) {
        ui.deferredSaveTask?.cancel()
        ui.deferredSaveTask = nil
        pendingFullReload = pendingFullReload || reload
        guard settings.save() else {
            saveFailed = true
            return
        }
        let shouldReload = pendingFullReload
        pendingFullReload = false
        saveFailed = false
        iCloudSync.shared.scheduleUpload(settings)
        if shouldReload { onChange() }
    }

    private func applyCommit(_ policy: SettingsCommitPolicy) {
        switch policy {
        case .fullReload:
            commit()
        case .saveOnly:
            persistSettings(reload: false)
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
                guard !Task.isCancelled else { return }
                persistSettings(reload: false)
            }
        }
    }

    private func flushDeferredSave() {
        guard ui.deferredSaveTask != nil || saveFailed else { return }
        persistSettings(reload: false)
    }
}
