import AppKit
import SwiftUI

/// 快捷输入面板的状态(含图片内容)
@MainActor
final class QuickInputModel: ObservableObject {
    @Published var text: String = ""
    @Published var actionID: String = ""
    @Published var imageData: Data? = nil   // #3 截图/粘贴的图片
    @Published var imageMimeType: String = "image/png"
    let settings: AppSettings
    var onSubmit: ((String, AIAction, Data?) -> Void)?

    init(settings: AppSettings) { self.settings = settings }

    func submit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || imageData != nil else { return }
        let act = settings.enabledActions.first(where: { $0.id == actionID })
            ?? settings.enabledActions.first
        guard let act = act else { return }
        onSubmit?(t, act, imageData)
        text = ""
        imageData = nil
    }

    /// 从剪贴板读取图片(#3)
    func pasteImageFromClipboard() {
        if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            imageData = image.snapAIPNGData()
            imageMimeType = "image/png"
        }
    }
}

struct QuickInputView: View {
    @ObservedObject var model: QuickInputModel
    var onClose: () -> Void
    var onCapture: () -> Void   // 触发截图

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                Text("SnapAI 快捷提问").font(.headline)
                Spacer()
                Menu {
                    ForEach(model.settings.enabledActions) { act in
                        Button {
                            model.actionID = act.id
                        } label: {
                            if act.id == model.actionID { Label(act.name, systemImage: "checkmark") }
                            else { Text(act.name) }
                        }
                    }
                } label: {
                    let name = model.settings.enabledActions.first(where: { $0.id == model.actionID })?.name ?? "动作"
                    Label(name, systemImage: "wand.and.stars").font(.caption)
                }
                .menuStyle(.borderlessButton).fixedSize()
            }

            // 图片预览
            if let img = model.imageData, let nsImg = NSImage(data: img) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: nsImg).resizable().scaledToFit().frame(maxHeight: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button { model.imageData = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).padding(2)
                }
            }

            TextField("输入你的问题,回车发送…", text: $model.text, onCommit: { model.submit() })
                .textFieldStyle(.roundedBorder).font(.body)

            HStack {
                // #3 截图 / 粘贴图片
                Button { onCapture() } label: {
                    Label("截图", systemImage: "camera").font(.caption2)
                }
                .buttonStyle(.borderless).help("截取当前屏幕")
                Button { model.pasteImageFromClipboard() } label: {
                    Label("粘贴图片", systemImage: "photo").font(.caption2)
                }
                .buttonStyle(.borderless).help("粘贴剪贴板中的图片")

                Spacer()
                Text("⏎ 发送").font(.caption2).foregroundStyle(.secondary)
                Button("发送") { model.submit() }
                    .disabled(model.text.trimmingCharacters(in: .whitespaces).isEmpty && model.imageData == nil)
            }
        }
        .padding(16).frame(width: 460).background(.ultraThinMaterial)
    }
}

/// 管理快捷输入面板
@MainActor
final class QuickInputController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    let model: QuickInputModel

    init(model: QuickInputModel) { self.model = model; super.init() }

    func toggle() {
        if let p = panel, p.isVisible { hide() } else { show() }
    }

    func show() {
        let view = QuickInputView(model: model, onClose: { [weak self] in self?.hide() },
                                  onCapture: { [weak self] in self?.captureScreen() })
        let hosting = NSHostingView(rootView: view)
        let panel: FloatingPanel
        if let existing = self.panel {
            panel = existing; panel.contentView = hosting
        } else {
            panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 150))
            panel.contentView = hosting; panel.minSize = NSSize(width: 360, height: 90)
            self.panel = panel
        }
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let origin = NSPoint(x: vf.midX - panel.frame.width / 2, y: vf.midY + 80)
            panel.setFrameOrigin(origin)
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installEscMonitor()
    }

    func hide() { panel?.orderOut(nil); removeEscMonitor() }

    /// #3 截图:隐藏所有窗口 → 等300ms → 用 screencapture 命令截全屏 → 重新显示
    private func captureScreen() {
        let visible = NSApp.windows.filter { $0.isVisible }
        visible.forEach { $0.orderOut(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            let tmpPath = "/tmp/snapai_ss_\(Int(Date().timeIntervalSince1970)).png"
            let proc = Process()
            proc.launchPath = "/usr/sbin/screencapture"
            proc.arguments = ["-x", tmpPath]   // -x 静音
            proc.launch()
            proc.waitUntilExit()
            if let data = try? Data(contentsOf: URL(fileURLWithPath: tmpPath)) {
                self?.model.imageData = data
                self?.model.imageMimeType = "image/png"
                try? FileManager.default.removeItem(atPath: tmpPath)
            }
            visible.forEach { $0.makeKeyAndOrderFront(nil) }
            self?.show()
        }
    }

    private var escMonitor: Any?
    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.hide(); return nil }
            return event
        }
    }
    private func removeEscMonitor() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
    }
}

// MARK: - NSImage 扩展

extension NSImage {
    /// 转换为 PNG Data(用于 API 上传)
    func snapAIPNGData() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
