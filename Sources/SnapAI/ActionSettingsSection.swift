import AppKit
import SnapAILogic
import SwiftUI
import UniformTypeIdentifiers

struct ActionSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var navigation: SettingsNavigationModel
    @ObservedObject var ui: AISettingsUI
    let commit: () -> Void
    let applyCommit: (SettingsCommitPolicy) -> Void

    private let labelWidth: CGFloat = 76
    @State private var pendingRestoreHotKeys = false
    @State private var pendingDeleteAction: AIAction?
    @StateObject private var actionLibraryNotice = SnapAITransientState<ResultOperationFeedback>()

    private func flashNotice(_ message: String, isError: Bool = false) {
        actionLibraryNotice.show(isError ? .error(message) : .success(message), autoDismiss: isError ? 4 : 1.8)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    actionToolbar
                    hotKeyNotice
                    quickPanelHotKeyCard
                    systemPromptSection
                    ForEach(settings.actions) { action in
                        actionCard(action)
                            .id(action.id)
                    }
                }
                .padding(SnapAIUI.edgePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .snapAIScrollEdge()
            .onChange(of: ui.expandedActionID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .top) }
            }
        }
        .snapAIConfirmDestructive(
            isPresented: $pendingRestoreHotKeys,
            title: "恢复默认快捷键",
            message: "将覆盖所有动作的当前快捷键,此操作不可撤销。"
        ) {
            settings.restoreDefaultHotKeys()
            ui.hotKeyError = nil
            ui.hotKeyConflictDestination = nil
            commit()
        }
        .confirmationDialog(
            "删除动作「\(pendingDeleteAction?.name ?? "")」",
            isPresented: Binding(get: { pendingDeleteAction != nil },
                                 set: { if !$0 { pendingDeleteAction = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeleteAction
        ) { action in
            Button("删除", role: .destructive) { deleteAction(action.id) }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("该动作及其快捷键将被移除,此操作不可撤销。")
        }
        .overlay(alignment: .bottom) {
            if let notice = actionLibraryNotice.value {
                Label(notice.message, systemImage: notice.systemImage)
                    .font(SnapAIUI.Typography.sectionLabel)
                    .foregroundStyle(SnapAIUI.StatusColor.tint(for: notice.kind))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .snapAIGlassPill(tint: .secondary)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                    .accessibilityLabel(notice.message)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: actionLibraryNotice.value)
    }

    private var actionToolbar: some View {
        HStack(spacing: 12) {
            Text("\(settings.enabledActions.count) 个已启用，共 \(settings.actions.count) 个动作")
                .font(SnapAIUI.Typography.metaText)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("导入动作库…", systemImage: "square.and.arrow.down", action: importActionLibrary)
                Button("导出动作库…", systemImage: "square.and.arrow.up", action: exportActionLibrary)
                Divider()
                Button("恢复默认快捷键…", systemImage: "keyboard.badge.ellipsis", action: restoreDefaultHotKeys)
            } label: {
                Label("管理", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            addActionMenu
                .fixedSize()
        }
        .controlSize(.regular)
    }

    private var systemPromptSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("System Prompt 对所有动作生效，用于设定共同的语气与回答方式。")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
                promptEditor(text: systemPromptBinding, height: 120)
                    .accessibilityLabel("全局 System Prompt")
            }
            .padding(.top, 12)
        } label: {
            Text("全局提示词")
                .font(SnapAIUI.Typography.sectionTitle)
        }
        .padding(16)
        .snapAIGlassCard()
    }

    private var addActionMenu: some View {
        Menu {
            Button("空白动作") {
                addAction(AIAction(name: "新动作", icon: "wand.and.stars",
                                   prompt: "请处理下面的文字:\n\n{{text}}"))
            }
            Divider()
            ForEach(ActionTemplateLibrary.builtIns) { template in
                Button(template.title) {
                    addAction(template.action.aiAction)
                }
            }
        } label: {
            Label("添加动作", systemImage: "plus")
        }
    }

    @ViewBuilder
    private var hotKeyNotice: some View {
        if let hotKeyError = ui.hotKeyError {
            HStack(spacing: 8) {
                Label(hotKeyError, systemImage: "exclamationmark.triangle.fill")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(SnapAIUI.StatusColor.warning)
                if let destination = ui.hotKeyConflictDestination {
                    Button("查看冲突项") {
                        showHotKeyConflictTarget(destination)
                    }
                    .buttonStyle(.link)
                    .font(SnapAIUI.Typography.metaText)
                }
            }
        }
    }

    private var quickPanelHotKeyCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("快捷提问")
                    .font(SnapAIUI.Typography.sectionTitle)
                Text("直接打开输入面板，无需先选中文字。")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
                HotKeyRecorder(combo: Binding(
                    get: { settings.quickPanelHotKey },
                    set: { newVal in
                        if let conflict = hotKeyConflictDetail(for: newVal,
                                                               excludingActionID: nil,
                                                               includeQuickPanel: false) {
                            ui.hotKeyError = "快捷提问面板与「\(conflict.title)」冲突,未保存"
                            ui.hotKeyConflictDestination = conflict.target
                            return
                        }
                        ui.hotKeyConflictDestination = nil
                        ui.hotKeyError = HotKeyConflictDetector.systemWarning(for: newVal)
                        settings.quickPanelHotKey = newVal
                        commit()
                    }
                ))
                    .frame(width: 138, height: 34)
                    .help(HotKeyRecorderText.instructions)
                    .accessibilityLabel("快捷提问的全局快捷键")
        }
        .padding(16)
        .snapAIGlassCard()
    }

    @ViewBuilder
    private func actionCard(_ action: AIAction) -> some View {
        let isExpanded = ui.expandedActionID == action.id
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Button {
                    ui.expandedActionID = isExpanded ? nil : action.id
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: action.icon.isEmpty ? "wand.and.stars" : action.icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(action.isEnabled ? Color.accentColor : .secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(action.name)
                                .font(SnapAIUI.Typography.sectionTitle)
                                .foregroundStyle(action.isEnabled ? .primary : .secondary)
                                .lineLimit(1)
                            if !isExpanded {
                                Text(String(action.prompt.prefix(100)).replacingOccurrences(of: "\n", with: " "))
                                    .font(SnapAIUI.Typography.metaText)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        if let hotKey = action.hotKey {
                            SnapAIKeycap(text: hotKey.displayString)
                        }
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "收起动作 \(action.name)" : "编辑动作 \(action.name)")
                Toggle("启用\(action.name)", isOn: bindingForAction(action.id, \.isEnabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if isExpanded {
                actionEditor(action).padding(.top, 16)
            }
        }
        .padding(16)
        .snapAIGlassCard()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actionEditor(_ action: AIAction) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            editorRow("名称") {
                TextField("动作名称", text: bindingForAction(action.id, \.name, policy: .deferredSave), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("动作提示词")
                    .font(SnapAIUI.Typography.sectionTitle)
                promptEditor(text: bindingForAction(action.id, \.prompt, policy: .deferredSave), height: 120)
                    .accessibilityLabel("\(action.name)的 Prompt")
                Text("使用 {{text}} 引用选中文字，{{lang}} 引用目标语言。")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            actionHotKeyEditor(action)
            Toggle("翻译类动作(显示语言切换)", isOn: bindingForAction(action.id, \.isTranslation))
            if action.isTranslation {
                editorRow("目标语言") {
                    Picker("", selection: bindingForAction(action.id, \.targetLanguage)) {
                        ForEach(TargetLanguage.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().frame(width: 200, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Toggle("完成后进入替换确认", isOn: bindingForAction(action.id, \.replaceByDefault))
                Text("先展示差异预览，确认后才写回原应用。")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Toggle("保存到历史记录", isOn: bindingForAction(action.id, \.saveHistory))
                Text("关闭后，此动作的结果不会进入历史记录。")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 14) {
                    editorRow("图标") {
                        TextField("SF Symbol 名，如 wand.and.stars", text: bindingForAction(action.id, \.icon, policy: .deferredSave), onCommit: commit)
                            .textFieldStyle(.roundedBorder)
                    }
                    editorRow("分组") {
                        TextField("分组名，留空则不分组", text: bindingForAction(action.id, \.group, policy: .deferredSave), onCommit: commit)
                            .textFieldStyle(.roundedBorder)
                    }
                    actionProviderEditor(action)
                    Toggle("启用 Thinking / 推理模式", isOn: bindingForAction(action.id, \.thinkingMode))
                    if action.thinkingMode { thinkingBudgetEditor(action) }
                }
                .padding(.top, 12)
            } label: {
                Text("更多选项 · 图标、分组、模型与推理")
                    .font(SnapAIUI.Typography.metaText)
            }
            deleteActionRow(action).padding(.top, 8)
        }
        .font(SnapAIUI.Typography.bodyText)
    }

    private func actionHotKeyEditor(_ action: AIAction) -> some View {
        editorRow("快捷键") {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    HotKeyRecorder(combo: Binding(
                        get: { action.hotKey ?? HotKeyCombo(keyCode: 0, modifiers: 0) },
                        set: { newVal in
                            guard let idx = settings.actions.firstIndex(where: { $0.id == action.id }) else { return }
                            if newVal.modifiers != 0,
                               let conflict = hotKeyConflictDetail(for: newVal,
                                                                  excludingActionID: action.id,
                                                                  includeQuickPanel: true) {
                                ui.hotKeyError = "动作「\(action.name)」与「\(conflict.title)」冲突,未保存"
                                ui.hotKeyConflictDestination = conflict.target
                                return
                            }
                            ui.hotKeyConflictDestination = nil
                            ui.hotKeyError = HotKeyConflictDetector.systemWarning(for: newVal)
                            settings.actions[idx].hotKey = newVal.modifiers == 0 ? nil : newVal
                            commit()
                        }
                    ))
                    .frame(width: 138, height: 32)
                    if action.hotKey != nil {
                        Button("清除") {
                            guard let idx = settings.actions.firstIndex(where: { $0.id == action.id }) else { return }
                            settings.actions[idx].hotKey = nil
                            commit()
                        }.controlSize(.small)
                    }
                }
                Text(HotKeyRecorderText.instructions)
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let conflict = hotkeyConflictDetail(for: action) {
                    HStack(spacing: 8) {
                        Label("与「\(conflict.title)」冲突", systemImage: "exclamationmark.triangle.fill")
                            .font(SnapAIUI.Typography.metaText)
                            .foregroundStyle(SnapAIUI.StatusColor.warning)
                        Button("查看冲突项") {
                            showHotKeyConflictTarget(conflict.target)
                        }
                        .buttonStyle(.link)
                        .font(SnapAIUI.Typography.metaText)
                    }
                }
            }
        }
    }

    private func actionProviderEditor(_ action: AIAction) -> some View {
        editorRow("供应商") {
            HStack(spacing: 6) {
                Picker("", selection: Binding(
                    get: { action.providerID ?? "" },
                    set: { newVal in
                        guard let idx = settings.actions.firstIndex(where: { $0.id == action.id }) else { return }
                        settings.actions[idx].providerID = newVal.isEmpty ? nil : newVal
                        settings.actions[idx].modelOverride = nil
                        commit()
                    }
                )) {
                    Text("使用全局").tag("")
                    ForEach(settings.providers.filter { $0.isEnabled }) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                .labelsHidden().frame(maxWidth: .infinity)
                if let pid = action.providerID,
                   let p = settings.providers.first(where: { $0.id == pid }) {
                    let models = p.models.map { $0.name }
                    Picker("", selection: Binding(
                        get: { action.modelOverride ?? "" },
                        set: { newVal in
                            guard let idx = settings.actions.firstIndex(where: { $0.id == action.id }) else { return }
                            settings.actions[idx].modelOverride = newVal.isEmpty ? nil : newVal
                            commit()
                        }
                    )) {
                        Text("供应商默认").tag("")
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func thinkingBudgetEditor(_ action: AIAction) -> some View {
        editorRow("思考预算") {
            HStack {
                TextField("tokens", value: Binding<Int>(
                    get: { action.thinkingBudget },
                    set: { newValue in
                        guard let idx = settings.actions.firstIndex(where: { $0.id == action.id }) else { return }
                        settings.actions[idx].thinkingBudget = AIAction.sanitizedThinkingBudget(newValue)
                        commit()
                    }
                ), formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder).frame(width: 80)
                Text("tokens(Anthropic 专用,建议 4000–16000)")
                    .font(SnapAIUI.Typography.metaText).foregroundStyle(.secondary)
            }
        }
    }

    private func deleteActionRow(_ action: AIAction) -> some View {
        HStack {
            // 排序与删除同属「管理此动作」,合并到底部一行,标题行因此更清爽。
            Button {
                moveAction(action.id, up: true)
            } label: {
                Label("上移", systemImage: "chevron.up")
            }
            .controlSize(.small)
            .disabled(settings.actions.first?.id == action.id)
            .help("上移到上一行")
            .accessibilityLabel("将动作 \(action.name) 上移")
            Button {
                moveAction(action.id, up: false)
            } label: {
                Label("下移", systemImage: "chevron.down")
            }
            .controlSize(.small)
            .disabled(settings.actions.last?.id == action.id)
            .help("下移到下一行")
            .accessibilityLabel("将动作 \(action.name) 下移")
            Spacer()
            Button(role: .destructive) {
                pendingDeleteAction = action
            } label: { Label("删除动作", systemImage: "trash") }
            .disabled(settings.actions.count <= 1)
        }
    }

    private func deleteAction(_ id: String) {
        settings.actions.removeAll { $0.id == id }
        if ui.expandedActionID == id { ui.expandedActionID = nil }
        commit()
    }

    private var systemPromptBinding: Binding<String> {
        Binding(
            get: { settings.systemPrompt },
            set: { newValue in
                settings.systemPrompt = newValue
                applyCommit(.deferredSave)
            }
        )
    }

    private func bindingForAction<V>(_ id: String,
                                     _ keyPath: WritableKeyPath<AIAction, V>,
                                     policy: SettingsCommitPolicy = .fullReload) -> Binding<V> {
        Binding(
            get: { (settings.actions.first(where: { $0.id == id }) ?? AIAction())[keyPath: keyPath] },
            set: { newValue in
                guard let idx = settings.actions.firstIndex(where: { $0.id == id }) else { return }
                settings.actions[idx][keyPath: keyPath] = newValue
                applyCommit(policy)
            }
        )
    }

    private func addAction(_ template: AIAction) {
        var action = template
        action.id = UUID().uuidString
        action.hotKey = nil
        settings.actions.append(action)
        ui.expandedActionID = action.id
        commit()
    }

    private func restoreDefaultHotKeys() {
        pendingRestoreHotKeys = true
    }

    private func importActionLibrary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "导入 SnapAI 动作库"
        guard panel.runModal() == .OK,
              let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            flashNotice("读取文件失败", isError: true)
            return
        }
        guard let imported = try? ActionTemplateLibrary.importedActions(from: data) else {
            flashNotice("文件格式无法识别", isError: true)
            return
        }
        let installed = ActionTemplateLibrary.installedActions(from: imported,
                                                               existingActions: settings.actions.actionTemplateActions).aiActions
        guard !installed.isEmpty else {
            flashNotice("没有可导入的新动作")
            return
        }
        let count = installed.count
        settings.actions.append(contentsOf: installed)
        ui.expandedActionID = installed.first?.id
        commit()
        flashNotice("已导入 \(count) 个动作")
    }

    private func exportActionLibrary() {
        guard let data = try? ActionTemplateLibrary.exportBundleData(actions: settings.actions.actionTemplateActions) else {
            flashNotice("导出失败，没有可导出的动作", isError: true)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SnapAI-Actions.json"
        panel.title = "导出 SnapAI 动作库"
        guard panel.runModal() == .OK,
              let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            flashNotice("已导出到 \(url.lastPathComponent)")
        } catch {
            flashNotice("写入文件失败", isError: true)
        }
    }

    private func moveAction(_ id: String, up: Bool) {
        guard let idx = settings.actions.firstIndex(where: { $0.id == id }) else { return }
        let target = up ? idx - 1 : idx + 1
        guard target >= 0, target < settings.actions.count else { return }
        settings.actions.swapAt(idx, target)
        commit()
    }

    private func hotkeyConflictDetail(for action: AIAction) -> HotKeyConflictDetector.Conflict? {
        guard let hk = action.hotKey, hk.modifiers != 0 else { return nil }
        return hotKeyConflictDetail(for: hk, excludingActionID: action.id, includeQuickPanel: true)
    }

    private func hotKeyConflictDetail(for combo: HotKeyCombo,
                                      excludingActionID: String?,
                                      includeQuickPanel: Bool) -> HotKeyConflictDetector.Conflict? {
        HotKeyConflictDetector.conflictDetail(for: combo,
                                              actions: settings.actions,
                                              excludingActionID: excludingActionID,
                                              quickPanelHotKey: settings.quickPanelHotKey,
                                              includeQuickPanel: includeQuickPanel)
    }

    private func showHotKeyConflictTarget(_ target: HotKeyConflictDetector.Conflict.Target) {
        navigation.select(.actions)
        switch target {
        case .action(let id):
            ui.expandedActionID = id
        case .quickPanel:
            ui.expandedActionID = nil
            ui.hotKeyError = "冲突项在上方「快捷提问面板」"
            ui.hotKeyConflictDestination = nil
        }
    }

    private func editorRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(SnapAIUI.Typography.metaText)
                .frame(width: labelWidth, alignment: .trailing)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func promptEditor(text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(SnapAIUI.Typography.bodyText)
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(height: height)
            .background(SnapAIUI.Surface.field)
            .clipShape(RoundedRectangle(cornerRadius: SnapAIUI.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SnapAIUI.controlRadius)
                    .stroke(SnapAIUI.Surface.divider, lineWidth: 1)
            )
    }
}
