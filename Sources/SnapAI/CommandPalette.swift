import SwiftUI
import AppKit

struct CommandPaletteItem: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var keywords: String
    var perform: () -> Void

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return title.lowercased().contains(q)
            || subtitle.lowercased().contains(q)
            || keywords.lowercased().contains(q)
    }
}

final class CommandPaletteModel: ObservableObject {
    @Published var query: String = ""
}

@MainActor
final class CommandPaletteController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private let itemProvider: () -> [CommandPaletteItem]
    private let model = CommandPaletteModel()
    private var escMonitor: Any?

    init(itemProvider: @escaping () -> [CommandPaletteItem]) {
        self.itemProvider = itemProvider
        super.init()
    }

    func show() {
        let wrapped = itemProvider().map { item in
            CommandPaletteItem(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                systemImage: item.systemImage,
                keywords: item.keywords,
                perform: { [weak self] in
                    self?.hide()
                    item.perform()
                }
            )
        }
        model.query = ""
        let view = CommandPaletteView(items: wrapped,
                                      model: model,
                                      onClose: { [weak self] in self?.hide() })
        let hosting = NSHostingView(rootView: view)
        let panel: FloatingPanel
        if let existing = self.panel {
            panel = existing
            panel.contentView = hosting
        } else {
            panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420))
            panel.minSize = NSSize(width: 480, height: 320)
            panel.contentView = hosting
            panel.delegate = self
            self.panel = panel
        }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installEscMonitor()
        DispatchQueue.main.async { [weak hosting] in
            if let textField = hosting?.firstSubview(ofType: NSTextField.self) {
                hosting?.window?.makeFirstResponder(textField)
            }
        }
    }

    func hide() {
        removeEscMonitor()
        panel?.orderOut(nil)
    }

    // 失焦时关闭
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.hide(); return nil }   // esc
            return event
        }
    }

    private func removeEscMonitor() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
    }
}

private extension NSView {
    func firstSubview<T: NSView>(ofType type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let match = subview.firstSubview(ofType: type) {
                return match
            }
        }
        return nil
    }
}

struct CommandPaletteView: View {
    let items: [CommandPaletteItem]
    @ObservedObject var model: CommandPaletteModel
    var onClose: () -> Void

    private var filteredItems: [CommandPaletteItem] {
        Array(items.filter { $0.matches(model.query) }.prefix(40))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索动作、模型、历史记录或设置…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit {
                        filteredItems.first?.perform()
                    }
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("关闭命令面板")
            }
            .padding(14)

            Divider()

            if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("没有匹配项")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredItems) { item in
                            Button {
                                item.perform()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: item.systemImage)
                                        .frame(width: 24)
                                        .foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.callout.weight(.medium))
                                            .lineLimit(1)
                                        Text(item.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 560, height: 420)
        .background(.ultraThinMaterial)
    }
}
