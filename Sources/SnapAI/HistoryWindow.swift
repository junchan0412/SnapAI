import SwiftUI
import AppKit
import SnapAILogic

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: AppSettings
    private let reopen: (HistoryEntry) -> Void
    private let model: HistoryWindowModel

    init(settings: AppSettings, reopen: @escaping (HistoryEntry) -> Void) {
        self.settings = settings
        self.reopen = reopen
        self.model = HistoryWindowModel(settings: settings)
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
    let settings: AppSettings
    @ObservedObject var model: HistoryWindowModel
    var reopen: (HistoryEntry) -> Void
    @StateObject private var operationCoordinator = ResultOperationCoordinator()
    @FocusState private var focusedTagID: String?

    var body: some View {
        let presentation = model.presentation
        VStack(alignment: .leading, spacing: 12) {
            historyToolbar(presentation: presentation)
            filterSummaryBar(presentation: presentation)

            if presentation.entries.isEmpty {
                VStack(spacing: 8) {
                    if model.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                    Text(model.isRefreshing ? "正在筛选历史记录…" :
                            (presentation.totalCount == 0 ? "暂无历史记录" : "没有匹配的历史记录"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(presentation.entries) { entry in
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
        .overlay(alignment: .bottom) {
            ResultOperationFeedbackHost(coordinator: operationCoordinator)
                .frame(maxWidth: 420)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    private func historyToolbar(presentation: HistoryWindowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("搜索历史、语义、原文、结果或模型…", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                    .onSubmit { model.refreshImmediately() }
                Toggle(isOn: $model.favoriteOnly) {
                    Image(systemName: "star.fill")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("只看收藏")
                Button {
                    model.resetFilters()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
                .help("清空筛选")
                Spacer(minLength: 0)
                historyToolbarActions(presentation: presentation)
            }
            HStack(spacing: 8) {
                Picker("", selection: $model.actionFilter) {
                    ForEach(presentation.actionNames, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 132)
                Picker("", selection: $model.modelFilter) {
                    ForEach(presentation.modelNames, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 158)
                Picker("", selection: $model.tagFilter) {
                    ForEach(presentation.tagNames, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 132)
                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
    }

    private func historyToolbarActions(presentation: HistoryWindowPresentation) -> some View {
        HStack(spacing: 6) {
            savedFilterMenu
            Button {
                copyFilteredHistory()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
            .disabled(model.isRefreshing || presentation.entries.isEmpty)
            .help("复制当前筛选结果")
            Button {
                exportFilteredHistory()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
            .disabled(model.isRefreshing || presentation.entries.isEmpty)
            .help("导出当前筛选结果")
            Button {
                createContextProfileFromFilteredHistory()
            } label: {
                Image(systemName: "text.badge.plus")
            }
            .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
            .disabled(model.isRefreshing || !presentation.canCreateContextProfile)
            .help(presentation.canCreateContextProfile ? "从当前筛选创建上下文包" : "当前筛选没有可写入上下文的历史内容")
        }
    }

    private var savedFilterMenu: some View {
        Menu {
            Button {
                saveCurrentFilter()
            } label: {
                Label("保存当前筛选…", systemImage: "plus")
            }
            .disabled(model.criteria.isDefault)

            if !model.savedFilters.isEmpty {
                Divider()
                ForEach(model.savedFilters) { filter in
                    Button {
                        applySavedFilter(filter)
                    } label: {
                        Label(filter.displayName, systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .help(filter.subtitle)
                }

                Divider()
                Menu("删除已保存筛选") {
                    ForEach(model.savedFilters) { filter in
                        Button(role: .destructive) {
                            settings.deleteSavedHistoryFilter(id: filter.id)
                        } label: {
                            Text(filter.displayName)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "bookmark")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 26, height: 26)
        .help("已保存筛选")
    }

    private func filterSummaryBar(presentation: HistoryWindowPresentation) -> some View {
        let criteria = presentation.criteria
        return HStack(spacing: 6) {
            SnapAIStatusPill(title: "\(presentation.entries.count) / \(presentation.totalCount)",
                             systemImage: "clock.arrow.circlepath")
            if model.isRefreshing {
                SnapAIStatusPill(title: "筛选中", systemImage: "arrow.triangle.2.circlepath", tint: .accentColor)
            }
            if criteria.favoriteOnly {
                SnapAIStatusPill(title: "收藏", systemImage: "star.fill", tint: .yellow, filled: true)
            }
            if criteria.actionFilter != HistoryFilterCriteria.allActions {
                SnapAIStatusPill(title: criteria.actionFilter, systemImage: "wand.and.stars")
            }
            if criteria.modelFilter != HistoryFilterCriteria.allModels {
                SnapAIStatusPill(title: criteria.modelFilter, systemImage: "cpu")
            }
            if criteria.tagFilter != HistoryFilterCriteria.allTags {
                SnapAIStatusPill(title: "#\(criteria.tagFilter)", systemImage: "tag")
            }
            Spacer(minLength: 0)
        }
    }

    private func historyCard(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                SnapAIStatusPill(title: entry.displayActionName,
                                 systemImage: "wand.and.stars",
                                 tint: .accentColor,
                                 filled: true)
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
                .buttonStyle(SnapAIIconButtonStyle(size: 24))
                .help(entry.isFavorite ? "取消收藏" : "收藏")
                Button {
                    guard let output = entry.copyableOutputText else { return }
                    operationCoordinator.copy(text: output,
                                              successMessage: "结果已复制",
                                              emptyMessage: "该记录没有可复制的结果。")
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 24))
                .disabled(entry.copyableOutputText == nil)
                .help(entry.copyableOutputText == nil ? "该记录未保存结果" : "复制结果")
                Button {
                    operationCoordinator.copy(text: entry.markdownExport,
                                              successMessage: "完整记录已复制",
                                              emptyMessage: "该记录没有可复制的内容。")
                } label: {
                    Image(systemName: "doc.richtext")
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 24))
                .help("复制完整记录")
                Button {
                    reopen(entry)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 24))
                .disabled(!entry.canReopen)
                .help(entry.reopenHelpText)
                Button(role: .destructive) {
                    settings.deleteHistory(id: entry.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 24))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .snapAISurface(padding: 9, fillOpacity: SnapAIUI.quietFillOpacity)
    }

    private func copyFilteredHistory() {
        let export = historyCollectionExport()
        operationCoordinator.copy(text: export.markdown,
                                  successMessage: "已复制 \(export.entries.count) 条历史记录",
                                  emptyMessage: "当前没有可复制的历史记录。")
    }

    private func exportFilteredHistory(date: Date = Date()) {
        let export = historyCollectionExport(date: date)
        operationCoordinator.export(
            markdown: export.markdown,
            suggestedFilename: ResultExportFilename.suggested(
                actionName: "SnapAI-History",
                timestamp: Int(date.timeIntervalSince1970)
            ),
            emptyMessage: "当前没有可导出的历史记录。"
        )
    }

    private func saveCurrentFilter() {
        let alert = NSAlert()
        alert.messageText = "保存历史筛选"
        alert.informativeText = "为当前筛选组合命名,之后可从历史窗口快速套用。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = suggestedSavedFilterName()
        field.placeholderString = "筛选名称"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = settings.upsertSavedHistoryFilter(name: field.stringValue,
                                              criteria: model.criteria)
    }

    private func applySavedFilter(_ filter: SavedHistoryFilter) {
        commitTagDrafts(except: nil)
        model.apply(criteria: filter.criteria)
    }

    private func suggestedSavedFilterName() -> String {
        AppSettings.sanitizedSavedHistoryFilterName(model.criteria.summaryText)
    }

    private func createContextProfileFromFilteredHistory() {
        let presentation = model.presentation
        guard let draft = HistoryContextProfileBuilder.draft(entries: presentation.entries,
                                                              criteria: presentation.criteria) else {
            return
        }
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
        HistoryCollectionExport(entries: model.presentation.entries,
                                criteria: model.presentation.criteria,
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
