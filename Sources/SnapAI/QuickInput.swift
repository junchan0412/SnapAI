import AppKit
import SwiftUI

/// 快捷输入面板的状态
@MainActor
final class QuickInputModel: ObservableObject {
    @Published var text: String = ""
    @Published var actionID: String = ""
    let settings: AppSettings
    var onSubmit: ((String, AIAction) -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func submit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let act = settings.enabledActions.first(where: { $0.id == actionID })
            ?? settings.enabledActions.first
            ?? AIAction.defaults()[0]
        onSubmit?(t, act)
        text = ""
    }
}

struct QuickInputView: View {
    @ObservedObject var model: QuickInputModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                Text("SnapAI 快捷提问").font(.headline)
                Spacer()
                // 动作选择
                Menu {
                    ForEach(model.settings.enabledActions) { act in
                        Button {
                            model.actionID = act.id
                        } label: {
                            if act.id == model.actionID {
                                Label(act.name, systemImage: "checkmark")
                            } else { Text(act.name) }
                        }
                    }
                } label: {
                    let name = model.settings.enabledActions.first(where: { $0.id == model.actionID })?.name ?? "动作"
                    Label(name, systemImage: "wand.and.stars").font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            TextField("输入你的问题,回车发送…", text: $model.text, onCommit: {
                model.submit()
            })
            .textFieldStyle(.roundedBorder)
            .font(.body)

            HStack {
                Text("⏎ 发送 · esc 关闭").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("发送") { model.submit() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(model.text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 460)
        .background(.ultraThinMaterial)
    }
}

/// 管理快捷输入面板
@MainActor
final class QuickInputController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    let model: QuickInputModel

    init(model: QuickInputModel) {
        self.model = model
        super.init()
    }

    func toggle() {
        if let p = panel, p.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let view = QuickInputView(model: model, onClose: { [weak self] in self?.hide() })
        let hosting = NSHostingView(rootView: view)
        let panel: FloatingPanel
        if let existing = self.panel {
            panel = existing
            panel.contentView = hosting
        } else {
            panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 130))
            panel.contentView = hosting
            panel.minSize = NSSize(width: 360, height: 90)
            self.panel = panel
        }
        // 居中靠上显示
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let size = panel.frame.size
            let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.midY + 80)
            panel.setFrameOrigin(origin)
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installEscMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        removeEscMonitor()
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
