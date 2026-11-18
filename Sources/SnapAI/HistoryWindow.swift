import SwiftUI
import AppKit
import SnapAILogic

struct HistoryWindowView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: HistoryWindowModel
    var reopen: (HistoryEntry) -> Void
    var resume: ((ConversationSession) -> Void)? = nil
    var embeddedInWorkspace: Bool = false
    var onSettingsCommit: (() -> Void)? = nil

    @State private var showConversationLibrary = false
    @State private var showRetentionSettings = false
    @State private var showClearHistoryConfirm = false
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
            SnapAIFormDivider(inset: 0)

            if presentation.entries.isEmpty {
                emptyState(presentation: presentation)
            } else {
                HSplitView {
                    historyList(presentation: presentation)
                        .frame(minWidth: 236, idealWidth: 276, maxWidth: 330)
                    if let entry = selectedEntry(in: presentation) {
                        historyDetail(entry)
                            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(embeddedInWorkspace ? Color.clear : SnapAIUI.Surface.canvas)
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
        .sheet(isPresented: $showConversationLibrary) {
            ConversationLibraryView(settings: settings, restore: { resume?($0) })
        }
        .background {
            Button("搜索历史记录") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
        .overlay(alignment: .bottom) {
            ResultOperationFeedbackHost(coordinator: operationCoordinator)
                .frame(maxWidth: 460)
                .padding(14)
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
        .snapAIConfirmDestructive(
            isPresented: $showClearHistoryConfirm,
            title: "清空全部历史记录",
            message: "将永久删除全部历史记录、已保存会话及其本机图片，此操作不可撤销。"
        ) {
            guard settings.clearHistory() else {
                operationCoordinator.showError("未能清空全部历史或会话，请稍后重试。")
                return
            }
            onSettingsCommit?()
            operationCoordinator.showSuccess("已清空全部历史记录")
        }
    }

    private func selectedEntry(in presentation: HistoryWindowPresentation) -> HistoryEntry? {
        presentation.entries.first { $0.id == selectedEntryID } ?? presentation.entries.first
    }

    private func historyToolbar(presentation: HistoryWindowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !embeddedInWorkspace {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("历史与会话")
                        .font(SnapAIUI.Typography.windowTitle)
                    Text("\(presentation.entries.count) 条")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("搜索原文、结果、模型或语义…", text: $model.query)
                        .accessibilityLabel("搜索历史记录")
                        .textFieldStyle(.plain)
                        .font(SnapAIUI.Typography.bodyText)
                        .focused($searchFocused)
                        .onSubmit { model.refreshImmediately() }
                    if model.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else if !model.query.isEmpty {
                        Button {
                            model.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空搜索")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6.5)
                .snapAIGlassField(radius: SnapAIUI.controlRadius)

                Button {
                    model.favoriteOnly.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.favoriteOnly ? "star.fill" : "star")
                            .foregroundStyle(model.favoriteOnly ? SnapAIUI.StatusColor.warning : .secondary)
                        Text("收藏")
                    }
                    .snapAIChip(active: model.favoriteOnly)
                }
                .buttonStyle(.plain)

                Button {
                    showFilters.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.criteria.isDefault ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                        Text("筛选")
                    }
                    .snapAIChip(active: !model.criteria.isDefault)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showFilters) { filterPopover(presentation: presentation) }

                savedFilterMenu

                if resume != nil {
                    Button {
                        showConversationLibrary = true
                    } label: {
                        Label("已存会话", systemImage: "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                }

                Menu {
                    Button("复制筛选结果", systemImage: "doc.on.doc", action: copyFilteredHistory)
                    Button("导出筛选结果…", systemImage: "square.and.arrow.down") {
                        exportFilteredHistory()
                    }
                    Button("转为上下文包…", systemImage: "text.badge.plus", action: createContextProfileFromFilteredHistory)
                        .disabled(!presentation.canCreateContextProfile)
                    Divider()
                    Button("清空全部历史…", systemImage: "trash", role: .destructive) {
                        showClearHistoryConfirm = true
                    }
                    .disabled(settings.history.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 26, height: 26)
                }
                .disabled(model.isRefreshing)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("整理、导出与清空历史")

                Button {
                    showRetentionSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
                .help("历史保留策略与使用统计")
                .accessibilityLabel("历史保留策略")
                .popover(isPresented: $showRetentionSettings, arrowEdge: .bottom) {
                    retentionPopover
                }
            }

            if !model.criteria.isDefault {
                HStack(spacing: 8) {
                    Text(model.criteria.summaryText)
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button("重置筛选") { model.resetFilters() }
                        .buttonStyle(.link)
                        .font(SnapAIUI.Typography.metaText)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .snapAIChrome()
    }

    private var retentionPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("保留策略与动作统计")
                .font(SnapAIUI.Typography.sectionTitle)

            HStack {
                Text("最多保留条数")
                    .font(SnapAIUI.Typography.bodyText)
                Spacer()
                Stepper("\(settings.historyLimit) 条", value: $settings.historyLimit, in: 0...500, step: 10)
                    .font(SnapAIUI.Typography.metaText)
                    .accessibilityLabel("保留历史记录条数")
                    .onChange(of: settings.historyLimit) { onSettingsCommit?() }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("存储模式")
                        .font(SnapAIUI.Typography.bodyText)
                    Spacer()
                    Picker("保存内容", selection: $settings.historyContentStorage) {
                        ForEach(HistoryContentStorage.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 190)
                    .onChange(of: settings.historyContentStorage) { onSettingsCommit?() }
                }
                Text(settings.historyContentStorage.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !settings.actionUsageCounts.isEmpty {
                SnapAIFormDivider(inset: 0)
                HStack {
                    Text("动作累计触发（共 \(settings.actionUsageCounts.values.reduce(0, +)) 次）")
                        .font(SnapAIUI.Typography.metaText.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清零") {
                        settings.actionUsageCounts = [:]
                        onSettingsCommit?()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
                let sorted = settings.actionUsageCounts.sorted { $0.value > $1.value }.prefix(6)
                ForEach(sorted, id: \.key) { name, count in
                    HStack {
                        Text(name)
                            .font(SnapAIUI.Typography.metaText)
                        Spacer()
                        Text("\(count) 次")
                            .font(SnapAIUI.Typography.metaText)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            SnapAIFormDivider(inset: 0)
            HStack {
                Text("当前已存 \(settings.history.count) 条记录")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空全部…", role: .destructive) {
                    showRetentionSettings = false
                    showClearHistoryConfirm = true
                }
                .controlSize(.small)
                .disabled(settings.history.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func filterPopover(presentation: HistoryWindowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("按条件筛选").font(SnapAIUI.Typography.sectionTitle)
            Picker("动作", selection: $model.actionFilter) {
                ForEach(presentation.actionNames, id: \.self) { Text($0).tag($0) }
            }
            Picker("模型", selection: $model.modelFilter) {
                ForEach(presentation.modelNames, id: \.self) { Text($0).tag($0) }
            }
            Picker("标签", selection: $model.tagFilter) {
                ForEach(presentation.tagNames, id: \.self) { Text($0).tag($0) }
            }
            SnapAIFormDivider(inset: 0)
            HStack {
                Button("重置") { model.resetFilters() }
                    .disabled(model.criteria.isDefault)
                Spacer()
                Button("完成") { showFilters = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
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
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("已保存的筛选条件")
        .accessibilityLabel("已保存筛选")
    }

    private func historyList(presentation: HistoryWindowPresentation) -> some View {
        List(selection: Binding(
            get: { selectedEntry(in: presentation)?.id },
            set: { selectedEntryID = $0 }
        )) {
            ForEach(presentation.entries) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text(entry.displayActionName)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 4)
                        if entry.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(SnapAIUI.StatusColor.warning)
                                .accessibilityLabel("已收藏")
                        }
                        Text(entry.dateString)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Text(String((entry.sourceDisplayText ?? entry.outputDisplayText ?? entry.emptyContentPlaceholder).prefix(120)))
                        .font(.system(size: 12.5))
                        .lineLimit(2)
                    Text(entry.modelDisplayText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.vertical, 5)
                .tag(entry.id)
                .accessibilityElement(children: .combine)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .snapAIChrome()
    }

    private func historyDetail(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.displayActionName)
                        .font(.system(size: 15, weight: .semibold))
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
                .buttonStyle(SnapAIIconButtonStyle(size: 28, circular: false))
                .help(entry.isFavorite ? "取消收藏" : "收藏")
                .accessibilityLabel(entry.isFavorite ? "取消收藏" : "收藏")

                Menu {
                    Button("复制完整记录 (Markdown)", systemImage: "doc.richtext") {
                        operationCoordinator.copy(text: entry.markdownExport,
                                                  successMessage: "完整记录已复制",
                                                  emptyMessage: "该记录没有可复制的内容。")
                    }
                    Divider()
                    Button("删除记录…", systemImage: "trash", role: .destructive) { pendingDeleteEntry = entry }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("记录操作")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            SnapAIFormDivider(inset: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let source = entry.sourceDisplayText {
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                showSource.toggle()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "quote.opening")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text("原文")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    if !showSource {
                                        Text(source.prefix(90).split(whereSeparator: \.isWhitespace).joined(separator: " "))
                                            .font(SnapAIUI.Typography.metaText)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: showSource ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if showSource {
                                SnapAIFormDivider(inset: 11)
                                Text(source)
                                    .font(SnapAIUI.Typography.bodyText)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(11)
                            }
                        }
                        .snapAIGlassCard(radius: 8)
                    }

                    if let output = entry.outputDisplayText {
                        MarkdownView(text: output, onCopyCode: { code in
                            operationCoordinator.copy(text: code, successMessage: "代码已复制", emptyMessage: "代码块为空。")
                        })
                        .font(SnapAIUI.Typography.readingText)
                        .lineSpacing(4.5)
                        .textSelection(.enabled)
                    } else {
                        Label(entry.emptyContentPlaceholder, systemImage: "lock.doc")
                            .font(SnapAIUI.Typography.bodyText)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .snapAIScrollEdge()
            .id(entry.id)

            SnapAIFormDivider(inset: 0)

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "tag")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("添加标签（逗号分隔）", text: tagBinding(for: entry))
                        .accessibilityLabel("添加标签，用逗号分隔")
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($focusedTagID, equals: entry.id)
                        .onSubmit { commitTagDraft(id: entry.id) }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(maxWidth: 240)
                .snapAIGlassField(radius: 6)

                Spacer()

                Button {
                    reopen(entry)
                } label: {
                    Label("重新提问", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                .disabled(!entry.canReopen)
                .help(entry.reopenHelpText)

                Button {
                    operationCoordinator.copy(text: entry.copyableOutputText ?? "",
                                              successMessage: "结果已复制",
                                              emptyMessage: "该记录没有可复制的结果。")
                } label: {
                    Label("复制结果", systemImage: "doc.on.doc")
                }
                .buttonStyle(SnapAIPrimaryButtonStyle(compact: true))
                .disabled(entry.copyableOutputText == nil)
                .accessibilityLabel("复制\(entry.displayActionName)的结果")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .snapAIChrome()
        }
    }

    private func emptyState(presentation: HistoryWindowPresentation) -> some View {
        VStack(spacing: 12) {
            Image(systemName: presentation.totalCount == 0 ? "clock.arrow.circlepath" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(model.isRefreshing ? "正在筛选…" : presentation.totalCount == 0 ? (settings.historyLimit == 0 ? "历史记录已关闭" : "暂无历史记录") : "没有匹配的历史记录")
                .font(SnapAIUI.Typography.sectionTitle)
            Text(presentation.totalCount == 0
                 ? (settings.historyLimit == 0 ? "开启保留策略后，后续提问会记录在这里。" : "完成一次提问后，原文与结果会按隐私偏好保存在本机。")
                 : "请尝试其他关键词，或重置筛选条件。")
                .font(SnapAIUI.Typography.metaText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 340)
                .multilineTextAlignment(.center)
            if !model.criteria.isDefault {
                Button("清除当前筛选") { model.resetFilters() }
                    .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                    .padding(.top, 4)
            } else if settings.historyLimit == 0 {
                Button("开启历史记录（保留 100 条）") {
                    settings.historyLimit = 100
                    onSettingsCommit?()
                }
                .buttonStyle(SnapAIPrimaryButtonStyle(compact: true))
                .padding(.top, 4)
            }
        }
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
        alert.informativeText = "为当前筛选组合命名，之后可从书签菜单快速套用。"
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
