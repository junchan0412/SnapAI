import SwiftUI
import AppKit

final class PermissionHealthModel: ObservableObject {
    @Published var snapshot: PermissionHealthSnapshot
    private let settings: AppSettings
    private let hotKeyFailures: () -> [String]

    init(settings: AppSettings, hotKeyFailures: @escaping () -> [String]) {
        self.settings = settings
        self.hotKeyFailures = hotKeyFailures
        snapshot = PermissionHealthSnapshot.make(settings: settings,
                                                 hotKeyFailures: hotKeyFailures())
    }

    func refresh() {
        snapshot = PermissionHealthSnapshot.make(settings: settings,
                                                 hotKeyFailures: hotKeyFailures())
    }
}

@MainActor
final class PermissionHealthController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: AppSettings
    private let hotKeyFailures: () -> [String]
    private lazy var model = PermissionHealthModel(settings: settings, hotKeyFailures: hotKeyFailures)

    init(settings: AppSettings, hotKeyFailures: @escaping () -> [String]) {
        self.settings = settings
        self.hotKeyFailures = hotKeyFailures
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
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
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
                    copyDiagnostics()
                } label: {
                    Label("复制诊断", systemImage: "doc.on.doc")
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                healthRow("辅助功能", snapshot.accessibilityGranted, "读取选中文字、模拟复制/粘贴") {
                    openPrivacyPane("Privacy_Accessibility")
                }
                healthRow("屏幕录制", snapshot.screenCaptureGranted, "快捷提问中的截图能力") {
                    openPrivacyPane("Privacy_ScreenCapture")
                }
                healthRow("开机启动", snapshot.launchAtLogin, "登录后自动常驻菜单栏") {
                    LoginItem.setEnabled(!snapshot.launchAtLogin)
                    model.refresh()
                }
                healthRow("快捷键注册", snapshot.hotKeyFailures.isEmpty, snapshot.hotKeyFailures.isEmpty ? "全部正常" : snapshot.hotKeyFailures.joined(separator: "；")) {
                    model.refresh()
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                detailLine("版本", snapshot.appVersion)
                detailLine("macOS", snapshot.macOSVersion)
                detailLine("Bundle ID", snapshot.bundleID)
                detailLine("安装位置", snapshot.installPath)
                detailLine("当前模型", snapshot.activeModel)
                detailLine("签名", snapshot.signingSummary)
            }
            .font(.caption)

            Spacer()
        }
        .padding(18)
        .frame(width: 620, height: 430)
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot.diagnosticText, forType: .string)
    }

    private func openPrivacyPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
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
}
