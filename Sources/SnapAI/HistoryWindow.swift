import SwiftUI
import AppKit
import SnapAILogic

struct HistoryWindowView: View {
    let settings: AppSettings
    @ObservedObject var model: HistoryWindowModel
    var reopen: (HistoryEntry) -> Void
    @StateObject var operationCoordinator = ResultOperationCoordinator()
    @FocusState private var focusedTagID: String?
    @FocusState private var searchFocused: Bool
    @State private var pendingDeleteEntry: HistoryEntry?
    @State private var selectedEntryID: String?
    @State private var showFilters = false
    @State private var showSource = false

    var body: some View {
        let presentation = model.presentation
        VStack(spacing: 0) {
            historyToolbar(presentation: presentation)
            Divider()
            if presentation.entries.isEmpty {
                emptyState(presentation: presentation)
            } else {
                HSplitView {
                    historyList(presentation: presentation)
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 360)
                    if let entry = selectedEntry(in: presentation) {
                        historyDetail(entry)
                            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(SnapAIUI.Surface.canvas)
        .onChange(of: focusedTagID) { _, focusedID in
            commitTagDrafts(except: focusedID)
        }
        .onChange(of: selectedEntry(in: presentation)?.id) { _, _ in
            commitTagDrafts(except: nil)
            showSource = false
        }
        .onChange(of: presentation.entries.map(\.id)) { _, ids in
            if let selectedEntryID, !ids.contains(selectedEntryID) {
                self.selectedEntryID = ids.first
            }
        }
        .onDisappear { commitTagDrafts(except: nil) }
        .background {
            Button("搜索历史记录") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
        .overlay(alignment: .bottom) {
            ResultOperationFeedbackHost(coordinator: operationCoordinator)
                .frame(maxWidth: 480)
                .padding(16)
        }
        .confirmationDialog(
            "删除该历史记录？",
            isPresented: Binding(get: { pendingDeleteEntry != nil },
                                 set: { if !$0 { pendingDeleteEntry = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeleteEntry
        ) { entry in
            Button("删除", role: .destructive) {
                guard settings.deleteHistory(id: entry.id) else {
                    operationCoordinator.showError("删除失败，历史记录仍保留。请稍后重试。")
                    pendingDeleteEntry = nil
                    return
                }
                pendingDeleteEntry = nil
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("该记录将被永久删除，此操作不可撤销。")
        }
    }

    private func selectedEntry(in presentation: HistoryWindowPresentation) -> HistoryEntry? {
        presentation.entries.first { $0.id == selectedEntryID } ?? presentation.entries.first
    }

    private func historyToolbar(presentation: HistoryWindowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("历史记录")
                    .font(SnapAIUI.Typography.windowTitle)
                Text("\(presentation.entries.count) 条")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
                if model.isRefreshing { ProgressView().controlSize(.small) }
                Spacer()
                Menu {
                    Button("复制筛选结果", systemImage: "doc.on.doc", action: copyFilteredHistory)
                    Button("导出筛选结果…", systemImage: "square.and.arrow.down") {
                        exportFilteredHistory()
                    }
                    Button("创建上下文包…", systemImage: "text.badge.plus", action: createContextProfileFromFilteredHistory)
                        .disabled(!presentation.canCreateContextProfile)
                } label: {
                    Label("导出与整理", systemImage: "square.and.arrow.up")
                }
                .disabled(model.isRefreshing || presentation.entries.isEmpty)
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索原文、结果、模型或语义…", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(SnapAIUI.Typography.bodyText)
                        .focused($searchFocused)
                        .onSubmit { model.refreshImmediately() }
                    if !model.query.isEmpty {
                        Button {
                            model.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空搜索")
                    }
                }
                .padding(10)
                .background(SnapAIUI.Surface.content, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(SnapAIUI.Surface.border, lineWidth: 1))
                Toggle(isOn: $model.favoriteOnly) {
                    Label("收藏", systemImage: model.favoriteOnly ? "star.fill" : "star")
                }
                .toggleStyle(.button)
                Button { showFilters.toggle() } label: {
                    Label("筛选", systemImage: model.criteria.isDefault ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
                .popover(isPresented: $showFilters) { filterPopover(presentation: presentation) }
                savedFilterMenu
            }
            if !model.criteria.isDefault {
                HStack(spacing: 8) {
                    Text(model.criteria.summaryText)
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button("清除筛选") { model.resetFilters() }
                        .buttonStyle(.link)
                        .font(SnapAIUI.Typography.metaText)
                }
            }
        }
        .padding(20)
        .background(SnapAIUI.Surface.chrome)
    }

    private func filterPopover(presentation: HistoryWindowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("筛选历史记录").font(.headline)
            Picker("动作", selection: $model.actionFilter) {
                ForEach(presentation.actionNames, id: \.self) { Text($0).tag($0) }
            }
            Picker("模型", selection: $model.modelFilter) {
                ForEach(presentation.modelNames, id: \.self) { Text($0).tag($0) }
            }
            Picker("标签", selection: $model.tagFilter) {
                ForEach(presentation.tagNames, id: \.self) { Text($0).tag($0) }
            }
            Divider()
            HStack {
                Button("重置筛选") { model.resetFilters() }
                    .disabled(model.criteria.isDefault)
                Spacer()
                Button("完成") { showFilters = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private var savedFilterMenu: some View {
        Menu {
            Button("保存当前筛选…", systemImage: "plus", action: saveCurrentFilter)
                .disabled(model.criteria.isDefault)
            if !model.savedFilters.isEmpty {
                Divider()
                ForEach(model.savedFilters) { filter in
                    Button(filter.displayName) { applySavedFilter(filter) }
                        .help(filter.subtitle)
                }
                Divider()
                Menu("删除已保存筛选") {
                    ForEach(model.savedFilters) { filter in
                        Button(filter.displayName, role: .destructive) {
                            settings.deleteSavedHistoryFilter(id: filter.id)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "bookmark")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28)
        .help("已保存筛选")
        .accessibilityLabel("已保存筛选")
    }

    private func historyList(presentation: HistoryWindowPresentation) -> some View {
        List(selection: Binding(
            get: { selectedEntry(in: presentation)?.id },
            set: { selectedEntryID = $0 }
        )) {
            ForEach(presentation.entries) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(entry.displayActionName).font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 4)
                        if entry.isFavorite {
                            Image(systemName: "star.fill")
                                .foregroundStyle(SnapAIUI.StatusColor.warning)
                                .accessibilityLabel("已收藏")
                        }
                        Text(entry.dateString).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(String((entry.sourceDisplayText ?? entry.outputDisplayText ?? entry.emptyContentPlaceholder).prefix(140)))
                        .font(SnapAIUI.Typography.bodyText)
                        .lineLimit(2)
                    Text(entry.modelDisplayText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 8)
                .tag(entry.id)
                .accessibilityElement(children: .combine)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(SnapAIUI.Surface.chrome)
    }

    private func historyDetail(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.displayActionName).font(SnapAIUI.Typography.sectionTitle)
                    Text("\(entry.modelDisplayText) · \(entry.dateString)")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    if !settings.toggleHistoryFavorite(id: entry.id) {
                        operationCoordinator.showError("收藏状态保存失败，请稍后重试。")
                    }
                } label: {
                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(entry.isFavorite ? SnapAIUI.StatusColor.warning : Color.secondary)
                }
                .buttonStyle(SnapAIIconButtonStyle())
                .help(entry.isFavorite ? "取消收藏" : "收藏")
                .accessibilityLabel(entry.isFavorite ? "取消收藏" : "收藏")
                Menu {
                    Button("复制完整记录", systemImage: "doc.richtext") {
                        operationCoordinator.copy(text: entry.markdownExport,
                                                  successMessage: "完整记录已复制",
                                                  emptyMessage: "该记录没有可复制的内容。")
                    }
                    Divider()
                    Button("删除记录…", systemImage: "trash", role: .destructive) { pendingDeleteEntry = entry }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .accessibilityLabel("记录操作")
            }
            .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let source = entry.sourceDisplayText {
                        DisclosureGroup("原文", isExpanded: $showSource) {
                            Text(source)
                                .font(SnapAIUI.Typography.bodyText)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        }
                        .font(.system(size: 13, weight: .medium))
                    }
                    if let output = entry.outputDisplayText {
                        MarkdownView(text: output, onCopyCode: { code in
                            operationCoordinator.copy(text: code, successMessage: "代码已复制", emptyMessage: "代码块为空。")
                        })
                        .font(SnapAIUI.Typography.bodyText)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                    } else {
                        Label(entry.emptyContentPlaceholder, systemImage: "lock.doc")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .id(entry.id)
            Divider()
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "tag").foregroundStyle(.secondary)
                    TextField("添加标签，用逗号分隔", text: tagBinding(for: entry))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($focusedTagID, equals: entry.id)
                        .onSubmit { commitTagDraft(id: entry.id) }
                }
                HStack {
                    Button("重新提问", systemImage: "arrow.clockwise") { reopen(entry) }
                        .disabled(!entry.canReopen)
                        .help(entry.reopenHelpText)
                    Spacer()
                    Button("复制结果", systemImage: "doc.on.doc") {
                        operationCoordinator.copy(text: entry.copyableOutputText ?? "",
                                                  successMessage: "结果已复制",
                                                  emptyMessage: "该记录没有可复制的结果。")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(entry.copyableOutputText == nil)
                }
            }
            .padding(20)
            .background(SnapAIUI.Surface.chrome)
        }
        .background(SnapAIUI.Surface.canvas)
    }

    private func emptyState(presentation: HistoryWindowPresentation) -> some View {
        VStack(spacing: 16) {
            Image(systemName: presentation.totalCount == 0 ? "clock.arrow.circlepath" : "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(model.isRefreshing ? "正在筛选…" : presentation.totalCount == 0 ? "让每次灵感都有迹可循" : "没有匹配的历史记录")
                .font(SnapAIUI.Typography.sectionTitle)
            Text(presentation.totalCount == 0 ? "完成一次提问后，原文与结果会按你的隐私设置保存在这里。" : "试试其他关键词，或清除筛选条件。")
                .font(SnapAIUI.Typography.bodyText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            if !model.criteria.isDefault {
                Button("清除筛选") { model.resetFilters() }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}
