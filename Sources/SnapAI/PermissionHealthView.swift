import SwiftUI
import AppKit
import SnapAILogic

final class PermissionHealthModel: ObservableObject {
    @Published var snapshot: PermissionHealthSnapshot
    private let settings: AppSettings
    private let hotKeyFailures: () -> [String]
    private let textCaptureStatus: () -> String
    private let writeBackStatus: () -> String
    private let recentAIRequestStatus: () -> String

    init(settings: AppSettings,
         hotKeyFailures: @escaping () -> [String],
         textCaptureStatus: @escaping () -> String,
         writeBackStatus: @escaping () -> String,
         recentAIRequestStatus: @escaping () -> String) {
        self.settings = settings
        self.hotKeyFailures = hotKeyFailures
        self.textCaptureStatus = textCaptureStatus
        self.writeBackStatus = writeBackStatus
        self.recentAIRequestStatus = recentAIRequestStatus
        snapshot = PermissionHealthSnapshot.make(settings: settings,
                                                 hotKeyFailures: hotKeyFailures(),
                                                 textCaptureStatus: textCaptureStatus(),
                                                 writeBackStatus: writeBackStatus(),
                                                 recentAIRequestStatus: recentAIRequestStatus(),
                                                 installLogStatus: UpdateChecker.latestInstallLogStatus().permissionHealthStatus,
                                                 includeSigningSummary: false)
    }

    func refresh(includeSigningSummary: Bool = false) {
        snapshot = PermissionHealthSnapshot.make(settings: settings,
                                                 hotKeyFailures: hotKeyFailures(),
                                                 textCaptureStatus: textCaptureStatus(),
                                                 writeBackStatus: writeBackStatus(),
                                                 recentAIRequestStatus: recentAIRequestStatus(),
                                                 installLogStatus: UpdateChecker.latestInstallLogStatus().permissionHealthStatus,
                                                 includeSigningSummary: includeSigningSummary)
    }

    func fullSnapshot() -> PermissionHealthSnapshot {
        PermissionHealthSnapshot.make(settings: settings,
                                      hotKeyFailures: hotKeyFailures(),
                                      textCaptureStatus: textCaptureStatus(),
                                      writeBackStatus: writeBackStatus(),
                                      recentAIRequestStatus: recentAIRequestStatus(),
                                      installLogStatus: UpdateChecker.latestInstallLogStatus().permissionHealthStatus,
                                      includeSigningSummary: true)
    }
}

@MainActor
final class PermissionHealthController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: AppSettings
    private let hotKeyFailures: () -> [String]
    private let textCaptureStatus: () -> String
    private let writeBackStatus: () -> String
    private let recentAIRequestStatus: () -> String
    private lazy var model = PermissionHealthModel(settings: settings,
                                                   hotKeyFailures: hotKeyFailures,
                                                   textCaptureStatus: textCaptureStatus,
                                                   writeBackStatus: writeBackStatus,
                                                   recentAIRequestStatus: recentAIRequestStatus)

    init(settings: AppSettings,
         hotKeyFailures: @escaping () -> [String],
         textCaptureStatus: @escaping () -> String,
         writeBackStatus: @escaping () -> String,
         recentAIRequestStatus: @escaping () -> String) {
        self.settings = settings
        self.hotKeyFailures = hotKeyFailures
        self.textCaptureStatus = textCaptureStatus
        self.writeBackStatus = writeBackStatus
        self.recentAIRequestStatus = recentAIRequestStatus
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        model.refresh()
        let view = PermissionHealthView(model: model)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "权限与诊断"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 740, height: 640))
        window.minSize = NSSize(width: 620, height: 520)
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct PermissionHealthView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: PermissionHealthModel
    var embeddedInWorkspace: Bool = false
    var onNavigateToModels: (() -> Void)? = nil

    private var snapshot: PermissionHealthSnapshot { model.snapshot }
    private let healthColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    @StateObject private var copyNotice = SnapAITransientState<String>()
    @State private var showSystemDetails = false

    private func flashCopy(_ message: String) {
        copyNotice.show(message, autoDismiss: 1.4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !embeddedInWorkspace {
                standaloneHeader
                SnapAIFormDivider(inset: 0)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: SnapAIUI.looseSpacing) {
                    permissionsGroup
                    runtimeHealthGroup

                    if !snapshot.recoverySuggestions.isEmpty {
                        recoverySuggestionPanel
                    }

                    diagnosticsDisclosureGroup
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SnapAIUI.edgePadding)
            }
            .snapAIScrollEdge()
        }
        .background(embeddedInWorkspace ? Color.clear : SnapAIUI.Surface.canvas)
        .overlay(alignment: .bottom) {
            if let notice = copyNotice.value {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(SnapAIUI.Typography.sectionLabel)
                    .foregroundStyle(SnapAIUI.StatusColor.success)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .snapAIGlassPill(tint: SnapAIUI.StatusColor.success)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                    .accessibilityLabel(notice)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: copyNotice.value)
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    private var standaloneHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("权限与系统诊断")
                    .font(SnapAIUI.Typography.windowTitle)
                Text("检查系统授权、全局快捷键与本地服务状态。")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            toolbarActions
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .snapAIChrome()
    }

    private var toolbarActions: some View {
        HStack(spacing: 8) {
            Button {
                model.refresh()
            } label: {
                Label("重新检测", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SnapAISecondaryButtonStyle(compact: true))

            Menu {
                Button("复制精简诊断", systemImage: "doc.on.clipboard") {
                    copyDiagnostics(full: false)
                }
                Button("复制完整诊断", systemImage: "doc.on.doc") {
                    copyDiagnostics(full: true)
                }
            } label: {
                Label("复制诊断", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
            .fixedSize()
        }
    }

    // MARK: - 系统权限组

    private var permissionsGroup: some View {
        SnapAISectionGroup("macOS 系统授权") {
            if embeddedInWorkspace {
                toolbarActions
            }
        } content: {
            SnapAISettingRow(
                title: "辅助功能权限",
                subtitle: "用于无感读取选中文字与将润色结果写回原应用；快捷提问无需此权限。",
                icon: snapshot.accessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                iconTint: snapshot.accessibilityGranted ? SnapAIUI.StatusColor.success : SnapAIUI.StatusColor.warning
            ) {
                HStack(spacing: 8) {
                    SnapAISemanticPill(title: snapshot.accessibilityGranted ? "已授权" : "未授权",
                                       systemImage: snapshot.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.circle",
                                       tone: snapshot.accessibilityGranted ? .success : .warning)
                    Button(snapshot.accessibilityGranted ? "查看设置" : "前往授权") {
                        openPrivacyPane(.accessibility)
                    }
                    .buttonStyle(snapshot.accessibilityGranted
                                 ? AnyButtonStyle(SnapAISecondaryButtonStyle(compact: true))
                                 : AnyButtonStyle(SnapAIPrimaryButtonStyle(compact: true)))
                }
            }

            SnapAIFormDivider()

            SnapAISettingRow(
                title: "屏幕录制权限（按需可选）",
                subtitle: "仅在使用快捷提问的截图功能时需要；剪贴板粘贴图片无需此权限。",
                icon: "camera.viewfinder",
                iconTint: snapshot.screenCaptureGranted ? SnapAIUI.StatusColor.success : .secondary
            ) {
                HStack(spacing: 8) {
                    SnapAISemanticPill(title: snapshot.screenCaptureGranted ? "已授权" : "按需授权",
                                       systemImage: snapshot.screenCaptureGranted ? "checkmark.circle.fill" : "minus.circle",
                                       tone: snapshot.screenCaptureGranted ? .success : .neutral)
                    Button("打开设置") {
                        openPrivacyPane(.screenCapture)
                    }
                    .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                }
            }
        }
    }

    // MARK: - 运行健康概览网格

    private var runtimeHealthGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("运行健康检测")
                .font(SnapAIUI.Typography.sectionTitle)
                .padding(.horizontal, 2)

            LazyVGrid(columns: healthColumns, alignment: .leading, spacing: 10) {
                healthCard("全局快捷键",
                           snapshot.hotKeyFailures.isEmpty,
                           snapshot.hotKeyFailures.isEmpty ? "所有已启用动作快捷键均正常生效" : snapshot.hotKeyFailures.joined(separator: "；"),
                           actionTitle: "重新检测") {
                    model.refresh()
                }
                healthCard("AI 服务就绪",
                           snapshot.requestReadyProviderCount > 0,
                           requestReadinessText,
                           actionTitle: "配置模型与服务") {
                    if let onNavigateToModels {
                        onNavigateToModels()
                    } else {
                        openSettingsSection("provider")
                    }
                }
                healthCard("API 密钥存储",
                           snapshot.enabledProviderCount > 0 && snapshot.enabledProviderMissingAPIKeyCount == 0,
                           apiKeyHealthText,
                           actionTitle: "管理密钥") {
                    if let onNavigateToModels {
                        onNavigateToModels()
                    } else {
                        openSettingsSection("provider")
                    }
                }
                healthCard("登录自启动",
                           snapshot.launchAtLogin,
                           snapshot.launchAtLogin ? "登录系统后自动常驻菜单栏" : "当前未开启开机自启",
                           optional: true,
                           actionTitle: snapshot.launchAtLogin ? "关闭自启" : "开启自启") {
                    LoginItem.setEnabled(!snapshot.launchAtLogin)
                    model.refresh()
                }
            }
        }
    }

    private var recoverySuggestionPanel: some View {
        SnapAISectionGroup("建议优先处理") {
            Button {
                copyRecoverySuggestions()
            } label: {
                Label("复制建议", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(snapshot.recoverySuggestions, id: \.self) { suggestion in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(SnapAIUI.StatusColor.warning)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(SnapAIUI.Typography.bodyText.weight(.medium))
                            Text(suggestion.detail)
                                .font(SnapAIUI.Typography.metaText)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(14)
        }
    }

    private var diagnosticsDisclosureGroup: some View {
        SnapAISectionGroup("技术诊断详情（不含原文与密钥）") {
            EmptyView()
        } content: {
            DisclosureGroup(isExpanded: $showSystemDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    SnapAIFormDivider(inset: 0)
                    detailLine("应用版本", "\(snapshot.appVersion) · macOS \(snapshot.macOSVersion)")
                    detailLine("安装路径", "\(snapshot.installPath)（可写：\(snapshot.installDirectoryWritable ? "是" : "否")）")
                    detailLine("隔离与签名", "\(snapshot.quarantineStatus) · \(snapshot.signingSummary)", lineLimit: 3)
                    detailLine("当前模型", "\(snapshot.activeModel) · \(workModeStatusText)")
                    detailLine("最近请求", snapshot.recentAIRequestStatus, lineLimit: 3)
                    detailLine("取词 / 写回", "取词：\(snapshot.textCaptureStatus) · 写回：\(snapshot.writeBackStatus)")
                    detailLine("隐私与数据库", "脱敏：\(redactionStatusText) · 历史库：\(snapshot.historyStoreStatus)", lineLimit: 2)
                    installLogLine()
                }
                .font(SnapAIUI.Typography.metaText)
                .padding(.top, 8)
            } label: {
                Text("展开查看版本、签名、数据库与最近请求状态")
                    .font(SnapAIUI.Typography.bodyText)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .onChange(of: showSystemDetails) { _, expanded in
                if expanded {
                    model.refresh(includeSigningSummary: true)
                }
            }
        }
    }

    private var redactionStatusText: String {
        let state = snapshot.redactionEnabled ? "开启" : "关闭"
        return "\(state)（\(snapshot.redactionRuleCount) 条）"
    }

    private var apiKeyHealthText: String {
        snapshot.apiKeyHealthStatusLine
    }

    private var requestReadinessText: String {
        snapshot.requestReadinessStatusLine
    }

    private var workModeStatusText: String {
        "\(snapshot.workModeTitle)"
    }

    private func copyDiagnostics(full: Bool) {
        let targetSnapshot = full ? model.fullSnapshot() : snapshot
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full ? targetSnapshot.diagnosticText : targetSnapshot.briefDiagnosticText, forType: .string)
        flashCopy(full ? "完整诊断已复制" : "精简诊断已复制")
    }

    private func copyRecoverySuggestions() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot.recoverySuggestionClipboardText, forType: .string)
        flashCopy("修复建议已复制")
    }

    private func copyInstallLogPath() {
        guard snapshot.latestInstallLogAvailable else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot.latestInstallLogPath, forType: .string)
        flashCopy("日志路径已复制")
    }

    private func revealInstallLog() {
        guard snapshot.latestInstallLogAvailable else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: snapshot.latestInstallLogPath)])
    }

    private func openPrivacyPane(_ pane: SystemPrivacyPane) {
        NSWorkspace.shared.open(SystemPrivacySettings.url(for: pane))
    }

    private func openSettingsSection(_ section: String) {
        if let url = URL(string: "snapai://settings/\(section)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func healthCard(_ title: String,
                            _ ok: Bool,
                            _ note: String,
                            optional: Bool = false,
                            actionTitle: String,
                            action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: ok ? "checkmark.circle.fill" : optional ? "minus.circle" : "exclamationmark.circle.fill")
                    .foregroundStyle(ok ? SnapAIUI.StatusColor.success : optional ? .secondary : SnapAIUI.StatusColor.warning)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(SnapAIUI.Typography.bodyText.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(note)
                .font(SnapAIUI.Typography.metaText)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 30, alignment: .topLeading)
            Button(actionTitle, action: action)
                .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(13)
        .snapAIGlassCard()
    }

    private func detailLine(_ title: String, _ value: String, lineLimit: Int = 2) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func installLogLine() -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("更新日志")
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(snapshot.latestInstallLogPath)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if snapshot.latestInstallLogAvailable {
                Button("复制路径") { copyInstallLogPath() }
                    .buttonStyle(.link)
                Button("在访达中显示") { revealInstallLog() }
                    .buttonStyle(.link)
            }
        }
    }
}

private struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        _makeBody = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}
