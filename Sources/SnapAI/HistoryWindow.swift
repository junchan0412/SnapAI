import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class HistoryWindowModel: ObservableObject {
    @Published var query = ""
    @Published var actionFilter = HistoryFilterCriteria.allActions
    @Published var modelFilter = HistoryFilterCriteria.allModels
    @Published var tagFilter = HistoryFilterCriteria.allTags
    @Published var favoriteOnly = false
    @Published var tagDrafts: [String: String] = [:]

    func resetFilters() {
        query = ""
        actionFilter = HistoryFilterCriteria.allActions
        modelFilter = HistoryFilterCriteria.allModels
        tagFilter = HistoryFilterCriteria.allTags
        favoriteOnly = false
    }

    var criteria: HistoryFilterCriteria {
        HistoryFilterCriteria(query: query,
                              actionFilter: actionFilter,
                              modelFilter: modelFilter,
                              tagFilter: tagFilter,
                              favoriteOnly: favoriteOnly)
    }
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
        [HistoryFilterCriteria.allActions] + HistoryFilterCriteria.facetValues(settings.history.map(\.displayActionName))
    }

    private var modelNames: [String] {
        [HistoryFilterCriteria.allModels] + HistoryFilterCriteria.facetValues(settings.history.map(\.displayModelFilterName))
    }

    private var tagNames: [String] {
        [HistoryFilterCriteria.allTags] + HistoryFilterCriteria.facetValues(settings.history.flatMap(\.displayTags))
    }

    private var filtered: [HistoryEntry] {
        model.criteria.apply(to: settings.history)
    }

    private var contextProfileDraft: HistoryContextProfileDraft? {
        HistoryContextProfileBuilder.draft(entries: filtered,
                                           criteria: model.criteria)
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
                Button {
                    model.resetFilters()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.borderless)
                .help("清空筛选")
                Button {
                    copyFilteredHistory()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(filtered.isEmpty)
                .help("复制当前筛选结果")
                Button {
                    exportFilteredHistory()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(filtered.isEmpty)
                .help("导出当前筛选结果")
                Button {
                    createContextProfileFromFilteredHistory()
                } label: {
                    Image(systemName: "text.badge.plus")
                }
                .buttonStyle(.borderless)
                .disabled(contextProfileDraft == nil)
                .help(contextProfileDraft == nil ? "当前筛选没有可写入上下文的历史内容" : "从当前筛选创建上下文包")
            }

            HStack {
                Text("显示 \(filtered.count) / \(settings.history.count) 条")
                if model.favoriteOnly {
                    Text("收藏")
                }
                if model.actionFilter != HistoryFilterCriteria.allActions {
                    Text(model.actionFilter)
                }
                if model.modelFilter != HistoryFilterCriteria.allModels {
                    Text(model.modelFilter)
                }
                if model.tagFilter != HistoryFilterCriteria.allTags {
                    Text("#\(model.tagFilter)")
                }
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

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
                Text(entry.displayActionName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.16))
                    .clipShape(Capsule())
                Text(entry.modelDisplayText)
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
                    guard let output = entry.copyableOutputText else { return }
                    copy(output)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .disabled(entry.copyableOutputText == nil)
                .help(entry.copyableOutputText == nil ? "该记录未保存结果" : "复制结果")
                Button {
                    copy(entry.markdownExport)
                } label: {
                    Image(systemName: "doc.richtext")
                }
                .buttonStyle(.plain)
                .help("复制完整记录")
                Button {
                    reopen(entry)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(!entry.canReopen)
                .help(entry.reopenHelpText)
                Button(role: .destructive) {
                    settings.deleteHistory(id: entry.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("删除")
            }

            if let source = entry.sourceDisplayText {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            if let output = entry.outputDisplayText {
                Text(output)
                    .font(.callout)
                    .lineLimit(4)
                    .textSelection(.enabled)
            } else if entry.sourceDisplayText == nil {
                Text(entry.emptyContentPlaceholder)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
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

    private func copyFilteredHistory() {
        copy(historyCollectionExport().markdown)
    }

    private func exportFilteredHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SnapAI-History-\(Int(Date().timeIntervalSince1970)).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? historyCollectionExport().markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func createContextProfileFromFilteredHistory() {
        guard let draft = contextProfileDraft else { return }
        let willUpdate = settings.hasContextProfile(named: draft.name)

        let alert = NSAlert()
        alert.messageText = willUpdate ? "更新上下文包?" : "创建上下文包?"
        alert.informativeText = """
        将当前筛选中的 \(draft.includedCount) 条历史写入「\(draft.name)」并设为使用中。

        已跳过 \(draft.skippedCount) 条空内容、仅元信息或超出上限的记录。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: willUpdate ? "更新并启用" : "创建并启用")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let result = settings.upsertContextProfile(from: draft)
        iCloudSync.shared.scheduleUpload(settings)

        let done = NSAlert()
        done.messageText = result.didUpdate ? "上下文包已更新" : "上下文包已创建"
        done.informativeText = "后续请求会自动合并「\(result.profile.name)」中的历史上下文。你可以在设置页继续编辑。"
        done.addButton(withTitle: "好")
        done.runModal()
    }

    private func historyCollectionExport(date: Date = Date()) -> HistoryCollectionExport {
        HistoryCollectionExport(entries: filtered,
                                criteria: model.criteria,
                                date: date)
    }

    private func parseTags(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，;；")
        return text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func tagBinding(for entry: HistoryEntry) -> Binding<String> {
        Binding(
            get: { model.tagDrafts[entry.id] ?? entry.displayTags.joined(separator: ", ") },
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
