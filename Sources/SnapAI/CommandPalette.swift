import SwiftUI
import AppKit
import SnapAILogic

struct CommandPaletteItem: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var keywords: String
    var shortcutText: String? = nil
    var perform: () -> Void

    var searchableKeywords: String {
        MarkdownExportSafety.keywords([
            keywords,
            CommandPaletteMatcher.shortcutSearchKeywords(shortcutText)
        ], maxLength: 1_600)
    }

    func matches(_ query: String) -> Bool {
        CommandPaletteMatcher.matches(title: title,
                                      subtitle: subtitle,
                                      keywords: searchableKeywords,
                                      query: query)
    }

    static func uniqued(_ items: [CommandPaletteItem]) -> [CommandPaletteItem] {
        let ids = CommandIdentifier.uniqued(items.map(\.id))
        return zip(items, ids).map { item, id in
            var copy = item
            copy.id = id
            return copy
        }
    }
}

final class CommandPaletteModel: ObservableObject {
    @Published var query: String = "" {
        didSet {
            if query != oldValue {
                selectedIndex = 0
            }
        }
    }
    @Published var selectedIndex: Int = 0

    func filteredItems(from items: [CommandPaletteItem]) -> [CommandPaletteItem] {
        Array(CommandPaletteMatcher.ranked(items, query: query) { item in
            (title: item.title, subtitle: item.subtitle, keywords: item.searchableKeywords)
        }.prefix(40))
    }

    func moveSelection(delta: Int, itemCount: Int) {
        guard itemCount > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex + delta, 0), itemCount - 1)
    }

    func selectedItem(from items: [CommandPaletteItem]) -> CommandPaletteItem? {
        let filtered = filteredItems(from: items)
        guard !filtered.isEmpty else { return nil }
        let index = min(max(selectedIndex, 0), filtered.count - 1)
        return filtered[index]
    }
}

@MainActor
final class CommandPaletteController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private let itemProvider: () -> [CommandPaletteItem]
    private let model = CommandPaletteModel()
    private var escMonitor: Any?
    private var currentItems: [CommandPaletteItem] = []

    init(itemProvider: @escaping () -> [CommandPaletteItem]) {
        self.itemProvider = itemProvider
        super.init()
    }

    func show() {
        let wrapped = CommandPaletteItem.uniqued(itemProvider()).map { item in
            CommandPaletteItem(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                systemImage: item.systemImage,
                keywords: item.keywords,
                shortcutText: item.shortcutText,
                perform: { [weak self] in
                    self?.hide()
                    item.perform()
                }
            )
        }
        currentItems = wrapped
        model.query = ""
        model.selectedIndex = 0
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
        FloatingPanelPresentation.present(panel)
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
        currentItems = []
        FloatingPanelPresentation.dismiss(panel)
    }

    // 失焦时关闭
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: // esc
                self.hide()
                return nil
            case 125: // down
                self.model.moveSelection(delta: 1,
                                         itemCount: self.model.filteredItems(from: self.currentItems).count)
                return nil
            case 126: // up
                self.model.moveSelection(delta: -1,
                                         itemCount: self.model.filteredItems(from: self.currentItems).count)
                return nil
            case 36, 76: // return / keypad return
                self.model.selectedItem(from: self.currentItems)?.perform()
                return nil
            default:
                break
            }
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
    var openPaletteHint: String? = nil

    private var filteredItems: [CommandPaletteItem] {
        model.filteredItems(from: items)
    }

    private var selectedIndex: Int {
        guard !filteredItems.isEmpty else { return 0 }
        return min(max(model.selectedIndex, 0), filteredItems.count - 1)
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
                        model.selectedItem(from: items)?.perform()
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
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("没有匹配项")
                        .foregroundStyle(.secondary)
                    Text("试试输入「翻译」「润色」「切换模型」或「清空历史」等关键词。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: 360)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
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
                                        if let shortcutText = item.shortcutText, !shortcutText.isEmpty {
                                            Text(shortcutText)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background {
                                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                        .fill(Color.secondary.opacity(0.12))
                                                }
                                                .accessibilityLabel("快捷键 \(shortcutText)")
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                    .background {
                                        if index == selectedIndex {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color.accentColor.opacity(0.16))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedIndex) {
                        scrollToSelection(with: proxy)
                    }
                    .onChange(of: model.query) {
                        scrollToSelection(with: proxy)
                    }
                }
            }

            Divider()
            HStack(spacing: 14) {
                Label("↑↓ 选择", systemImage: "arrow.up.arrow.down")
                Label("↩ 执行", systemImage: "return")
                Label("Esc 关闭", systemImage: "escape")
                Spacer()
                if let hint = openPaletteHint, !hint.isEmpty {
                    Text("打开此面板:\(hint)")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 560, height: 420)
        .background(.ultraThinMaterial)
    }

    private func scrollToSelection(with proxy: ScrollViewProxy) {
        guard filteredItems.indices.contains(selectedIndex) else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(filteredItems[selectedIndex].id, anchor: .center)
        }
    }
}
