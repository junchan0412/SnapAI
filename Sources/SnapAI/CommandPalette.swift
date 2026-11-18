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
                recomputeFilteredItems()
            }
        }
    }
    @Published var selectedIndex: Int = 0
    @Published private(set) var filteredItems: [CommandPaletteItem] = []

    private var sourceItems: [CommandPaletteItem] = []

    func replaceItems(_ items: [CommandPaletteItem]) {
        sourceItems = items
        recomputeFilteredItems()
    }

    func filteredItems(from items: [CommandPaletteItem]) -> [CommandPaletteItem] {
        if items.count == sourceItems.count,
           zip(items, sourceItems).allSatisfy({ $0.id == $1.id }) {
            return filteredItems
        }
        return Self.rank(items, query: query)
    }

    func moveSelection(delta: Int, itemCount: Int? = nil) {
        let count = itemCount ?? filteredItems.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex + delta, 0), count - 1)
    }

    func selectedItem(from items: [CommandPaletteItem]? = nil) -> CommandPaletteItem? {
        let filtered = items.map { filteredItems(from: $0) } ?? filteredItems
        guard !filtered.isEmpty else { return nil }
        let index = min(max(selectedIndex, 0), filtered.count - 1)
        return filtered[index]
    }

    private func recomputeFilteredItems() {
        filteredItems = Self.rank(sourceItems, query: query)
        if selectedIndex >= filteredItems.count {
            selectedIndex = max(0, filteredItems.count - 1)
        }
    }

    private static func rank(_ items: [CommandPaletteItem], query: String) -> [CommandPaletteItem] {
        Array(CommandPaletteMatcher.ranked(items, query: query) { item in
            (title: item.title, subtitle: item.subtitle, keywords: item.searchableKeywords)
        }.prefix(40))
    }
}

@MainActor
final class CommandPaletteController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<CommandPaletteView>?
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
        model.replaceItems(wrapped)
        let view = CommandPaletteView(model: model,
                                      onClose: { [weak self] in self?.hide() })
        let panel: FloatingPanel
        if let existing = self.panel, let hostingView {
            panel = existing
            hostingView.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            hosting.safeAreaRegions = []
            panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 420))
            panel.minSize = NSSize(width: 500, height: 340)
            panel.contentView = hosting
            panel.delegate = self
            self.panel = panel
            self.hostingView = hosting
        }
        panel.title = "SnapAI 命令面板"
        panel.center()
        FloatingPanelPresentation.present(panel)
        NSApp.activate(ignoringOtherApps: true)
        installEscMonitor()
        DispatchQueue.main.async { [weak self] in
            guard let hosting = self?.hostingView else { return }
            if let textField = hosting.firstSubview(ofType: NSTextField.self) {
                hosting.window?.makeFirstResponder(textField)
            }
        }
    }

    func hide() {
        removeEscMonitor()
        currentItems = []
        model.replaceItems([])
        FloatingPanelPresentation.dismiss(panel)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if let editor = self.panel?.firstResponder as? NSTextView, editor.hasMarkedText() {
                return event
            }
            switch event.keyCode {
            case 53: // esc
                self.hide()
                return nil
            case 125: // down
                self.model.moveSelection(delta: 1)
                return nil
            case 126: // up
                self.model.moveSelection(delta: -1)
                return nil
            case 36, 76: // return / keypad return
                self.model.selectedItem()?.perform()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: CommandPaletteModel
    var onClose: () -> Void
    var openPaletteHint: String? = nil

    private var filteredItems: [CommandPaletteItem] { model.filteredItems }

    private var selectedIndex: Int {
        guard !filteredItems.isEmpty else { return 0 }
        return min(max(model.selectedIndex, 0), filteredItems.count - 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("搜索动作、切换模型、历史记录或设置…", text: $model.query)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("搜索动作、模型、历史记录或设置")
                    .font(.system(size: 16))
                    .onSubmit {
                        model.selectedItem()?.perform()
                    }
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                SnapAIKeycap(text: "Esc")
                    .onTapGesture { onClose() }
                    .accessibilityLabel("关闭命令面板")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            SnapAIFormDivider(inset: 0)

            if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("没有找到匹配命令")
                        .font(SnapAIUI.Typography.sectionTitle)
                        .foregroundStyle(.secondary)
                    Text("试试输入「翻译」「润色」「切换模型」或「清空历史」")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                paletteRow(item, isSelected: index == selectedIndex)
                                    .id(item.id)
                            }
                        }
                        .padding(8)
                    }
                    .snapAIScrollEdge()
                    .onChange(of: selectedIndex) {
                        scrollToSelection(with: proxy)
                    }
                    .onChange(of: model.query) {
                        scrollToSelection(with: proxy)
                    }
                }
            }

            SnapAIFormDivider(inset: 0)

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    SnapAIKeycap(text: "↑↓")
                    Text("选择")
                }
                HStack(spacing: 4) {
                    SnapAIKeycap(text: "↩")
                    Text("执行")
                }
                Spacer()
                if let hint = openPaletteHint, !hint.isEmpty {
                    Text("唤起快捷键：\(hint)")
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(filteredItems.count) 项可用")
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 340, maxHeight: .infinity)
        .snapAIFloatingPanelSurface()
    }

    private func paletteRow(_ item: CommandPaletteItem, isSelected: Bool) -> some View {
        Button {
            item.perform()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(
                        isSelected ? Color.accentColor : Color.accentColor.opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let shortcutText = item.shortcutText, !shortcutText.isEmpty {
                    SnapAIKeycap(text: shortcutText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.13))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func scrollToSelection(with proxy: ScrollViewProxy) {
        guard filteredItems.indices.contains(selectedIndex) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.08)) {
            proxy.scrollTo(filteredItems[selectedIndex].id, anchor: .center)
        }
    }
}
