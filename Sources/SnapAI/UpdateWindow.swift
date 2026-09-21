import AppKit
import SwiftUI
import SnapAILogic

/// 更新流程的可观察状态,驱动「发现新版本」与「下载进度」两个界面。
@MainActor
final class UpdateFlowModel: ObservableObject {
    enum Phase: Equatable {
        case available
        case downloading
        case installing
    }

    @Published var phase: Phase = .available
    @Published var receivedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var autoInstall: Bool

    let currentDisplay: String
    let latestDisplay: String
    let releaseTitle: String
    let releaseNotes: String
    let hasNotes: Bool

    var onInstall: @MainActor () -> Void = {}
    var onSkip: @MainActor () -> Void = {}
    var onRemindLater: @MainActor () -> Void = {}
    var onCancel: @MainActor () -> Void = {}
    var onAutoInstallChanged: @MainActor (Bool) -> Void = { _ in }

    init(currentDisplay: String,
         latestDisplay: String,
         releaseTitle: String,
         releaseNotes: String,
         hasNotes: Bool,
         autoInstall: Bool) {
        self.currentDisplay = currentDisplay
        self.latestDisplay = latestDisplay
        self.releaseTitle = releaseTitle
        self.releaseNotes = releaseNotes
        self.hasNotes = hasNotes
        self.autoInstall = autoInstall
    }

    var progressFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(receivedBytes) / Double(totalBytes)))
    }

    var isIndeterminate: Bool { totalBytes <= 0 }

    var byteProgressText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        guard totalBytes > 0 else { return formatter.string(fromByteCount: receivedBytes) }
        return "\(formatter.string(fromByteCount: receivedBytes)) / \(formatter.string(fromByteCount: totalBytes))"
    }
}

/// 根据阶段切换「可更新」与「下载中」视图;整体贴合统一窗口基底,无区域色差。
struct UpdateRootView: View {
    @ObservedObject var model: UpdateFlowModel

    var body: some View {
        Group {
            switch model.phase {
            case .available:
                UpdateAvailableView(model: model)
            case .downloading, .installing:
                UpdateProgressView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SnapAIUI.Surface.canvas)
    }
}

private struct UpdateAppIcon: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct UpdateAvailableView: View {
    @ObservedObject var model: UpdateFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                UpdateAppIcon(size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text("SnapAI 有新版本可用！")
                        .font(.system(size: 17, weight: .semibold))
                    Text("SnapAI \(model.latestDisplay) 现在可用——你当前使用的是 \(model.currentDisplay)。是否立即下载？")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            notesCard

            Toggle("今后自动下载并安装更新", isOn: Binding(
                get: { model.autoInstall },
                set: { model.autoInstall = $0; model.onAutoInstallChanged($0) }
            ))
            .toggleStyle(.checkbox)

            HStack(spacing: 12) {
                Button("跳过此版本") { model.onSkip() }
                    .controlSize(.large)
                Spacer(minLength: 0)
                Button("稍后提醒") { model.onRemindLater() }
                    .controlSize(.large)
                Button("安装更新") { model.onInstall() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 22)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.releaseTitle)
                .font(.system(size: 20, weight: .bold))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    if model.hasNotes {
                        MarkdownView(text: model.releaseNotes)
                            .textSelection(.enabled)
                    } else {
                        Text(model.releaseNotes)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .snapAIScrollEdge()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .snapAIGlassCard()
    }
}

struct UpdateProgressView: View {
    @ObservedObject var model: UpdateFlowModel

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            UpdateAppIcon(size: 56)
            VStack(alignment: .leading, spacing: 12) {
                Text(model.phase == .installing ? "正在安装，即将重启…" : "正在下载更新…")
                    .font(.system(size: 15, weight: .semibold))

                if model.phase == .installing || model.isIndeterminate {
                    ProgressView()
                        .progressViewStyle(.linear)
                } else {
                    ProgressView(value: model.progressFraction)
                        .progressViewStyle(.linear)
                }

                HStack(spacing: 12) {
                    Text(model.phase == .installing ? "校验签名并替换应用…" : model.byteProgressText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if model.phase == .downloading {
                        Button("取消") { model.onCancel() }
                            .controlSize(.large)
                    }
                }
            }
        }
        .padding(20)
    }
}

/// 承载更新界面的单窗口:发现新版本时无标题栏对话框;进入下载后显示标题并收缩为进度窗。
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    static let shared = UpdateWindowController()

    private var window: NSWindow?
    private var model: UpdateFlowModel?
    private var installTask: Task<Void, Never>?

    func present(model: UpdateFlowModel) {
        self.model = model
        let host = NSHostingController(rootView: UpdateRootView(model: model))
        if let window {
            window.contentViewController = host
        } else {
            let window = NSWindow(contentViewController: host)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            window.identifier = NSUserInterfaceItemIdentifier("SnapAI.UpdateWindow")
            self.window = window
        }
        configureForAvailable()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureForAvailable() {
        guard let window else { return }
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.title = "SnapAI 更新"
        window.setContentSize(NSSize(width: 660, height: 520))
        window.minSize = NSSize(width: 560, height: 440)
    }

    /// 进入下载:显示标准标题栏并把窗口收缩为紧凑进度窗,保持屏幕中心不变。
    func enterDownloading() {
        model?.phase = .downloading
        guard let window else { return }
        window.styleMask = [.titled, .closable]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.title = "正在更新 SnapAI"
        window.minSize = NSSize(width: 460, height: 160)

        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        window.setContentSize(NSSize(width: 520, height: 180))
        var frame = window.frame
        frame.origin = NSPoint(x: (center.x - frame.width / 2).rounded(),
                               y: (center.y - frame.height / 2).rounded())
        window.setFrame(frame, display: true, animate: true)
    }

    func setInstallTask(_ task: Task<Void, Never>) {
        installTask = task
    }

    /// 用户点「取消」下载:取消任务并关闭窗口。
    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
        close()
    }

    func close() {
        installTask = nil
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        // 若在下载中被关闭,连带取消下载任务。
        installTask?.cancel()
        installTask = nil
        model = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, !window.isVisible else { return }
            window.contentViewController = nil
        }
    }
}
