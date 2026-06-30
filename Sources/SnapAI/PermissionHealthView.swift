import SwiftUI
import AppKit

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
                                                 recentAIRequestStatus: recentAIRequestStatus())
    }

    func refresh() {
        snapshot = PermissionHealthSnapshot.make(settings: settings,
                                                 hotKeyFailures: hotKeyFailures(),
                                                 textCaptureStatus: textCaptureStatus(),
                                                 writeBackStatus: writeBackStatus(),
                                                 recentAIRequestStatus: recentAIRequestStatus())
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
        window.title = "权限健康中心"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 680, height: 560))
        window.minSize = NSSize(width: 620, height: 500)
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
    @ObservedObject var model: PermissionHealthModel
    private var snapshot: PermissionHealthSnapshot { model.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        healthRow("辅助功能", snapshot.accessibilityGranted, "读取选中文字、模拟复制/粘贴") {
                            openPrivacyPane(.accessibility)
                        }
                        healthRow("屏幕录制", snapshot.screenCaptureGranted, "快捷提问中的截图能力") {
                            openPrivacyPane(.screenCapture)
                        }
                        healthRow("开机启动", snapshot.launchAtLogin, "登录后自动常驻菜单栏") {
                            LoginItem.setEnabled(!snapshot.launchAtLogin)
                            model.refresh()
                        }
                        healthRow("快捷键注册", snapshot.hotKeyFailures.isEmpty, snapshot.hotKeyFailures.isEmpty ? "全部正常" : snapshot.hotKeyFailures.joined(separator: "；")) {
                            model.refresh()
                        }
                        healthRow("API Key", snapshot.enabledProviderMissingAPIKeyCount == 0, apiKeyHealthText) {
                            openSettingsSection("ai")
                        }
                        healthRow("AI 请求", snapshot.requestReadyProviderCount > 0, requestReadinessText) {
                            openSettingsSection("ai")
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if !snapshot.recoverySuggestions.isEmpty {
                        recoverySuggestionPanel
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        detailLine("版本", snapshot.appVersion)
                        detailLine("macOS", snapshot.macOSVersion)
                        detailLine("Bundle ID", snapshot.bundleID)
                        detailLine("安装位置", snapshot.installPath)
                        detailLine("安装目录可写", snapshot.installDirectoryWritable ? "是" : "否")
                        detailLine("Quarantine", snapshot.quarantineStatus)
                        installLogLine()
                        detailLine("当前模型", snapshot.activeModel)
                        detailLine("工作模式", workModeStatusText)
                        detailLine("AI 请求", requestReadinessDetailText)
                        detailLine("最近请求", snapshot.recentAIRequestStatus)
                        detailLine("API Key", apiKeyDetailText)
                        detailLine("修复建议", snapshot.recoverySuggestionStatusLine)
                        detailLine("上下文", contextStatusText)
                        detailLine("提示长度", promptLengthText)
                        detailLine("取词状态", snapshot.textCaptureStatus)
                        detailLine("写回状态", snapshot.writeBackStatus)
                        detailLine("隐私预览", snapshot.privacyPreviewEnabled ? "开启" : "关闭")
                        detailLine("本地脱敏", redactionStatusText)
                        detailLine("历史内容", snapshot.historyContentStorage.rawValue)
                        detailLine("签名", snapshot.signingSummary)
                    }
                    .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .frame(minWidth: 620,
               idealWidth: 680,
               maxWidth: .infinity,
               minHeight: 500,
               idealHeight: 560,
               maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            Text("权限健康中心")
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                model.refresh()
            } label: {
                Label("重新检测", systemImage: "arrow.clockwise")
            }
            Button {
                copyDiagnostics(full: false)
            } label: {
                Label("复制精简", systemImage: "doc.on.clipboard")
            }
            Button {
                copyDiagnostics(full: true)
            } label: {
                Label("复制完整", systemImage: "doc.on.doc")
            }
        }
    }

    private var redactionStatusText: String {
        let state = snapshot.redactionEnabled ? "开启" : "关闭"
        return "\(state) · 规则 \(snapshot.redactionRuleCount) 条 · 异常 \(snapshot.invalidRedactionRuleCount) 条"
    }

    private var apiKeyHealthText: String {
        snapshot.apiKeyHealthStatusLine
    }

    private var apiKeyDetailText: String {
        snapshot.apiKeyHealthDetailLine
    }

    private var requestReadinessText: String {
        snapshot.requestReadinessStatusLine
    }

    private var requestReadinessDetailText: String {
        snapshot.requestReadinessDetailLine
    }

    private var workModeStatusText: String {
        "\(snapshot.workModeTitle) · \(snapshot.workModeDetail)"
    }

    private var contextStatusText: String {
        let activeName = snapshot.activeContextProfileName == "none" ? "无" : snapshot.activeContextProfileName
        return "\(activeName) · 可用 \(snapshot.usableContextProfileCount)/\(snapshot.contextProfileCount) · 当前 \(snapshot.activeContextCharacterCount) 字"
    }

    private var promptLengthText: String {
        "全局 \(snapshot.globalSystemPromptCharacterCount) 字 · 实际 \(snapshot.effectiveSystemPromptCharacterCount) 字"
    }

    private var recoverySuggestionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(snapshot.recoverySuggestionStatusLine, systemImage: "lightbulb")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    copyRecoverySuggestions()
                } label: {
                    Label("复制建议", systemImage: "doc.on.clipboard")
                }
                .controlSize(.small)
            }
            ForEach(snapshot.recoverySuggestions, id: \.self) { suggestion in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(.caption.weight(.medium))
                        Text(suggestion.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func copyDiagnostics(full: Bool) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full ? snapshot.diagnosticText : snapshot.briefDiagnosticText, forType: .string)
    }

    private func copyRecoverySuggestions() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot.recoverySuggestionClipboardText, forType: .string)
    }

    private func copyInstallLogPath() {
        guard snapshot.latestInstallLogAvailable else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot.latestInstallLogPath, forType: .string)
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

    private func healthRow(_ title: String,
                           _ ok: Bool,
                           _ note: String,
                           action: @escaping () -> Void) -> some View {
        GridRow {
            Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
                .font(.body.weight(.medium))
            Text(note)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button(ok ? "查看" : "修复") { action() }
                .controlSize(.small)
        }
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func installLogLine() -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("安装日志")
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Text(snapshot.latestInstallLogPath)
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("复制路径") {
                copyInstallLogPath()
            }
            .controlSize(.small)
            .disabled(!snapshot.latestInstallLogAvailable)
            Button("显示") {
                revealInstallLog()
            }
            .controlSize(.small)
            .disabled(!snapshot.latestInstallLogAvailable)
        }
    }
}
