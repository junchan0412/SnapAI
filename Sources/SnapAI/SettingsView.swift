import SwiftUI
import SnapAILogic

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var navigation: SettingsNavigationModel
    var onChange: () -> Void
    @ObservedObject var pinState: SettingsWindowPinState
    var onPinChange: (Bool) -> Void
    var onReopenHistory: (HistoryEntry) -> Void = { _ in }
    var onResumeConversation: ((ConversationSession) -> Void)? = nil
    var hotKeyFailures: () -> [String] = { [] }
    var textCaptureStatus: () -> String = { "就绪" }
    var writeBackStatus: () -> String = { "就绪" }
    var recentAIRequestStatus: () -> String = { "none" }

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
        let base = status.isEmpty ? "尚未同步" : status
        return "（\(base)，v\(revision)）"
    }

    var body: some View {
        NavigationSplitView {
            SettingsWorkspaceSidebar(
                selection: Binding(
                    get: { navigation.selectedSection },
                    set: { navigation.select($0) }
                ),
                settings: settings,
                commit: commit,
                providerName: settings.activeProvider?.name,
                modelName: settings.model,
                shortcut: settings.quickPanelHotKey.displayString
            )
        } detail: {
            VStack(spacing: 0) {
                settingsHeader
                SnapAIFormDivider(inset: 0)
                settingsContentSurface
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SnapAIVisualEffect(material: .underWindowBackground).allowsHitTesting(false).ignoresSafeArea())
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 840, idealWidth: 980, minHeight: 600, idealHeight: 680)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("设置未能写入磁盘")
                            .font(.callout.weight(.semibold))
                        Text("当前修改在内存中仍有效，请检查磁盘空间或文件权限后重试。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("重试保存") { persistSettings(reload: pendingFullReload) }
                        .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                }
                .padding(12)
                .frame(maxWidth: 580)
                .snapAIGlassCard(radius: 10)
                .padding(16)
            }
        }
    }

    private var settingsHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(navigation.selectedSection.sidebarSection.title)
                    .font(SnapAIUI.Typography.windowTitle)
                Text(navigation.selectedSection.sidebarSection.subtitle)
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            pinButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isPinned ? Color.accentColor : .secondary)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(SnapAIIconButtonStyle(size: 28, circular: false))
        .background {
            RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous)
                .fill(isPinned ? SnapAIUI.Surface.selected : .clear)
        }
        .help(isPinned ? "已置顶窗口（点击取消置顶）" : "置顶主窗口")
        .accessibilityLabel(isPinned ? "设置窗口已置顶" : "设置窗口未置顶")
        .accessibilityValue(SettingsWindowPinCommand.accessibilityValue(isPinned: isPinned))
    }

    @ViewBuilder
    private var settingsContentSurface: some View {
        if navigation.selectedSection.sidebarSection == .history {
            historyTab
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            selectedSectionContent
                .frame(maxWidth: 880, maxHeight: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch navigation.selectedSection.sidebarSection {
        case .model, .provider:
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
        ModelSettingsSection(settings: settings,
                             navigation: navigation,
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

    private var historyTab: some View {
        HistorySettingsSection(settings: settings,
                               commit: commit,
                               onReopen: onReopenHistory,
                               onResume: onResumeConversation)
    }

    private var generalTab: some View {
        GeneralSettingsSection(settings: settings,
                               permissionState: perm,
                               ui: ui,
                               iCloudSyncStatusText: iCloudSyncStatusText,
                               commit: commit,
                               applyCommit: applyCommit)
    }

    private var permissionTab: some View {
        PermissionSettingsSection(settings: settings,
                                  permissionState: perm,
                                  navigation: navigation,
                                  hotKeyFailures: hotKeyFailures,
                                  textCaptureStatus: textCaptureStatus,
                                  writeBackStatus: writeBackStatus,
                                  recentAIRequestStatus: recentAIRequestStatus)
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
