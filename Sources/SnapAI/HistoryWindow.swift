import SwiftUI
import AppKit

final class HistoryWindowModel: ObservableObject {
    @Published var query = ""
    @Published var actionFilter = "全部动作"
    @Published var modelFilter = "全部模型"
    @Published var tagFilter = "全部标签"
    @Published var favoriteOnly = false
    @Published var tagDrafts: [String: String] = [:]
}

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: AppSettings
    private let reopen: (HistoryEntry) -> Void
    private let model = HistoryWindowModel()

    init(settings: AppSettings, reopen: @escaping (HistoryEntry) -> Void) {
        self.settings = settings
        self.reopen = reopen
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = HistoryWindowView(settings: settings, model: model, reopen: reopen)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "SnapAI 历史记录"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 760, height: 560))
        window.minSize = NSSize(width: 620, height: 420)
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

struct HistoryWindowView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: HistoryWindowModel
    var reopen: (HistoryEntry) -> Void
    @FocusState private var focusedTagID: String?

    private var actionNames: [String] {
        ["全部动作"] + Array(Set(settings.history.map(\.actionName))).sorted()
    }

    private var modelNames: [String] {
        ["全部模型"] + Array(Set(settings.history.map(\.model))).sorted()
    }

    private var tagNames: [String] {
        ["全部标签"] + Array(Set(settings.history.flatMap(\.tags))).sorted()
    }

    private var filtered: [HistoryEntry] {
        settings.history.filter { entry in
            if model.favoriteOnly && !entry.isFavorite { return false }
            if model.actionFilter != "全部动作" && entry.actionName != model.actionFilter { return false }
            if model.modelFilter != "全部模型" && entry.model != model.modelFilter { return false }
            if model.tagFilter != "全部标签" && !entry.tags.contains(model.tagFilter) { return false }
            let q = model.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return true }
            return entry.actionName.lowercased().contains(q)
                || entry.source.lowercased().contains(q)
                || entry.output.lowercased().contains(q)
                || entry.model.lowercased().contains(q)
                || entry.tags.joined(separator: " ").lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("搜索历史、原文、结果或模型…", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $model.actionFilter) {
                    ForEach(actionNames, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 130)
                Picker("", selection: $model.modelFilter) {
                    ForEach(modelNames, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 150)
                Picker("", selection: $model.tagFilter) {
                    ForEach(tagNames, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 130)
                Toggle(isOn: $model.favoriteOnly) {
                    Image(systemName: "star.fill")
                }
                .toggleStyle(.button)
                .help("只看收藏")
            }

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(settings.history.isEmpty ? "暂无历史记录" : "没有匹配的历史记录")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { entry in
                            historyCard(entry)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .onChange(of: focusedTagID) { _, focusedID in
            commitTagDrafts(except: focusedID)
        }
        .onDisappear {
            commitTagDrafts(except: nil)
        }
    }

    private func historyCard(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(entry.actionName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.16))
                    .clipShape(Capsule())
                Text("\(entry.provider) / \(entry.model)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(entry.dateString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    settings.toggleHistoryFavorite(id: entry.id)
                } label: {
                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                .help(entry.isFavorite ? "取消收藏" : "收藏")
                Button {
                    copy(entry.output)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("复制结果")
                Button {
                    reopen(entry)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("重新发起")
                Button(role: .destructive) {
                    settings.deleteHistory(id: entry.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("删除")
            }

            Text(entry.source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
            Text(entry.output)
                .font(.callout)
                .lineLimit(4)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                TextField("标签,用逗号分隔", text: tagBinding(for: entry), onCommit: {
                    commitTagDraft(id: entry.id)
                })
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .focused($focusedTagID, equals: entry.id)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func parseTags(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，;；")
        return text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func tagBinding(for entry: HistoryEntry) -> Binding<String> {
        Binding(
            get: { model.tagDrafts[entry.id] ?? entry.tags.joined(separator: ", ") },
            set: { model.tagDrafts[entry.id] = $0 }
        )
    }

    private func commitTagDraft(id: String) {
        guard let draft = model.tagDrafts[id] else { return }
        settings.updateHistoryTags(id: id, tags: parseTags(draft))
        model.tagDrafts[id] = nil
    }

    private func commitTagDrafts(except focusedID: String?) {
        for id in Array(model.tagDrafts.keys) where id != focusedID {
            commitTagDraft(id: id)
        }
    }
}
