import AppKit
import SnapAILogic
import SwiftUI
import UniformTypeIdentifiers

struct ActionSettingsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var settings: AppSettings
    @ObservedObject var navigation: SettingsNavigationModel
    @ObservedObject var ui: AISettingsUI
    let commit: () -> Void
    let applyCommit: (SettingsCommitPolicy) -> Void

    private let labelWidth: CGFloat = 68
    @State private var pendingRestoreHotKeys = false
    @State private var dropTargetActionID: String?
    @State private var pendingDeleteAction: AIAction?
    @State private var showSystemPrompt = false
    @StateObject private var actionLibraryNotice = SnapAITransientState<ResultOperationFeedback>()

    private func flashNotice(_ message: String, isError: Bool = false) {
        actionLibraryNotice.show(isError ? .error(message) : .success(message), autoDismiss: isError ? 4 : 1.8)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SnapAIUI.looseSpacing) {
                    hotKeyNotice
                    globalQuickInputAndPromptGroup
                    actionsGroup
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
            message: "将重置所有内置动作与快捷提问面板的快捷键，此操作不可撤销。"
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
            Text("该动作及其快捷键将被移除，此操作不可撤销。")
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: actionLibraryNotice.value)
    }

    // MARK: - 全局唤起与系统指令组

    private var globalQuickInputAndPromptGroup: some View {
        SnapAISectionGroup("全局唤起与指令基调") {
            EmptyView()
        } content: {
            SnapAISettingRow(
                title: "快捷提问浮窗",
                subtitle: "随时唤起悬浮输入框直接提问、粘贴图片或截图，无需先选中文字。",
                icon: "sparkles",
                iconTint: .accentColor
            ) {
                HotKeyRecorder(combo: Binding(
                    get: { settings.quickPanelHotKey },
                    set: { newVal in
                        if let conflict = hotKeyConflictDetail(for: newVal,
                                                               excludingActionID: nil,
                                                               includeQuickPanel: false) {
                            ui.hotKeyError = "快捷提问面板与「\(conflict.title)」冲突，未保存"
                            ui.hotKeyConflictDestination = conflict.target
                            return
                        }
                        ui.hotKeyConflictDestination = nil
                        ui.hotKeyError = HotKeyConflictDetector.systemWarning(for: newVal)
                        settings.quickPanelHotKey = newVal
                        commit()
                    }
                ))
                .frame(width: 136, height: 28)
                .help(HotKeyRecorderText.instructions)
                .accessibilityLabel("快捷提问的全局快捷键")
            }

            SnapAIFormDivider()

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    showSystemPrompt.toggle()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.indigo)
                            .frame(width: 24, height: 24)
                            .background(Color.indigo.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("全局系统提示词 (System Prompt)")
                                .font(SnapAIUI.Typography.bodyText.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("对所有动作生效，设定统一的语气风格与回答规范。")
                                .font(SnapAIUI.Typography.metaText)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: showSystemPrompt ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showSystemPrompt {
                    promptEditor(text: systemPromptBinding, height: 100)
                        .accessibilityLabel("全局 System Prompt")
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    // MARK: - 选区动作列表

    private var actionsGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("选区与快捷动作")
                            .font(SnapAIUI.Typography.sectionTitle)
                        SnapAIStatusPill(title: "已启用 \(settings.enabledActions.count)/\(settings.actions.count)",
                                         systemImage: "checkmark.circle",
                                         tint: .secondary)
                    }
                    Text("拖动左侧手柄调整菜单与面板中的排列顺序")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("导入动作库…", systemImage: "square.and.arrow.down", action: importActionLibrary)
                    Button("导出动作库…", systemImage: "square.and.arrow.up", action: exportActionLibrary)
                    Divider()
                    Button("恢复默认快捷键…", systemImage: "keyboard.badge.ellipsis", action: restoreDefaultHotKeys)
                } label: {
                    Label("管理", systemImage: "ellipsis.circle")
                }
                .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                .fixedSize()

                addActionMenu
            }
            .padding(.horizontal, 2)

            VStack(spacing: 9) {
                ForEach(settings.actions) { action in
                    actionCard(action)
                        .id(action.id)
                        .overlay {
                            RoundedRectangle(cornerRadius: SnapAIUI.cardRadius, style: .continuous)
                                .stroke(Color.accentColor.opacity(dropTargetActionID == action.id ? 0.8 : 0), lineWidth: 2)
                                .allowsHitTesting(false)
                        }
                }
            }
        }
    }

    private var addActionMenu: some View {
        Menu {
            Button("新建空白动作") {
                addAction(AIAction(name: "新动作", icon: "wand.and.stars",
                                   prompt: "请处理下面的文字：\n\n{{text}}"))
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
        .buttonStyle(SnapAIPrimaryButtonStyle(compact: true))
        .fixedSize()
    }

    @ViewBuilder
    private var hotKeyNotice: some View {
        if let hotKeyError = ui.hotKeyError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SnapAIUI.StatusColor.warning)
                Text(hotKeyError)
                    .font(SnapAIUI.Typography.metaText)
                Spacer()
                if let destination = ui.hotKeyConflictDestination {
                    Button("定位冲突项") {
                        showHotKeyConflictTarget(destination)
                    }
                    .buttonStyle(.link)
                    .font(SnapAIUI.Typography.metaText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(SnapAIUI.StatusColor.warning.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(SnapAIUI.StatusColor.warning.opacity(0.22), lineWidth: 0.75)
            }
        }
    }

    @ViewBuilder
    private func actionCard(_ action: AIAction) -> some View {
        let isExpanded = ui.expandedActionID == action.id
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SettingsDragHandle(name: action.name, id: action.id, contentType: .snapAISettingsAction)
                Button {
                    ui.expandedActionID = isExpanded ? nil : action.id
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: action.icon.isEmpty ? "wand.and.stars" : action.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(action.isEnabled ? Color.accentColor : .secondary)
                            .frame(width: 26, height: 26)
                            .background((action.isEnabled ? Color.accentColor : Color.secondary).opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(action.name)
                                    .font(SnapAIUI.Typography.bodyText.weight(.semibold))
                                    .foregroundStyle(action.isEnabled ? .primary : .secondary)
                                    .lineLimit(1)
                                if !action.group.isEmpty {
                                    Text(action.group)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 5.5)
                                        .padding(.vertical, 1)
                                        .background(SnapAIUI.Surface.control, in: Capsule())
                                }
                                if action.replaceByDefault {
                                    Text("默认写回")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 5.5)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.11), in: Capsule())
                                }
                            }
                            if !isExpanded {
                                Text(String(action.prompt.prefix(96)).replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 11))
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
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "收起动作 \(action.name)" : "编辑动作 \(action.name)")

                Toggle("启用\(action.name)", isOn: bindingForAction(action.id, \.isEnabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if isExpanded {
                SnapAIFormDivider(inset: 14)
                actionEditor(action)
                    .padding(14)
            }
        }
        .snapAIGlassCard()
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(SettingsReorderDropModifier(
            id: action.id,
            items: $settings.actions, contentType: .snapAISettingsAction,
            dropTargetID: $dropTargetActionID, commit: commit))
    }

    @ViewBuilder
    private func actionEditor(_ action: AIAction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                editorRow("名称") {
                    TextField("动作名称", text: bindingForAction(action.id, \.name, policy: .deferredSave), onCommit: commit)
                        .textFieldStyle(.roundedBorder)
                }
                editorRow("分组") {
                    TextField("可选菜单分组", text: bindingForAction(action.id, \.group, policy: .deferredSave), onCommit: commit)
                        .textFieldStyle(.roundedBorder)
                }
            }

            actionHotKeyEditor(action)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("提示词模板 (Prompt)")
                        .font(SnapAIUI.Typography.metaText.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("可用变量：{{text}} 选区文本 · {{lang}} 目标语言")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                promptEditor(text: bindingForAction(action.id, \.prompt, policy: .deferredSave), height: 108)
                    .accessibilityLabel("\(action.name)的 Prompt")
            }

            SnapAIFormDivider(inset: 0)

            HStack(spacing: 20) {
                Toggle("完成后进入差异替换确认", isOn: bindingForAction(action.id, \.replaceByDefault))
                Toggle("保存到历史记录", isOn: bindingForAction(action.id, \.saveHistory))
                Toggle("显示翻译语言选择", isOn: bindingForAction(action.id, \.isTranslation))
            }
            .font(SnapAIUI.Typography.metaText)

            if action.isTranslation {
                editorRow("默认语种") {
                    Picker("", selection: bindingForAction(action.id, \.targetLanguage)) {
                        ForEach(TargetLanguage.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .leading)
                }
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    editorRow("图标") {
                        TextField("SF Symbol 名称，例如 wand.and.stars", text: bindingForAction(action.id, \.icon, policy: .deferredSave), onCommit: commit)
                            .textFieldStyle(.roundedBorder)
                    }
                    actionProviderEditor(action)
                    HStack(spacing: 12) {
                        Toggle("启用推理模式 (Thinking)", isOn: bindingForAction(action.id, \.thinkingMode))
                            .font(SnapAIUI.Typography.metaText)
                        if action.thinkingMode {
                            thinkingBudgetEditor(action)
                        }
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("高级选项（指定专属模型、图标与推理预算）")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }

            SnapAIFormDivider(inset: 0)
            deleteActionRow(action)
        }
        .font(SnapAIUI.Typography.bodyText)
    }

    private func actionHotKeyEditor(_ action: AIAction) -> some View {
        editorRow("快捷键") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    HotKeyRecorder(combo: Binding(
                        get: { action.hotKey ?? HotKeyCombo(keyCode: 0, modifiers: 0) },
                        set: { newVal in
                            guard let idx = settings.actions.firstIndex(where: { $0.id == action.id }) else { return }
                            if newVal.modifiers != 0,
                               let conflict = hotKeyConflictDetail(for: newVal,
                                                                  excludingActionID: action.id,
                                                                  includeQuickPanel: true) {
                                ui.hotKeyError = "动作「\(action.name)」与「\(conflict.title)」冲突，未保存"
                                ui.hotKeyConflictDestination = conflict.target
                                return
                            }
                            ui.hotKeyConflictDestination = nil
                            ui.hotKeyError = HotKeyConflictDetector.systemWarning(for: newVal)
                            settings.actions[idx].hotKey = newVal.modifiers == 0 ? nil : newVal
                            commit()
                        }
                    ))
                    .frame(width: 136, height: 28)

                    if action.hotKey != nil {
                        Button("清除") {
                            guard let idx = settings.actions.firstIndex(where: { $0.id == action.id }) else { return }
                            settings.actions[idx].hotKey = nil
                            commit()
                        }
                        .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                    }

                    Text("点击录制，Delete 清除，Esc 取消")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

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
        editorRow("指定模型") {
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { action.providerID ?? "" },
                    set: { newVal in
                        guard let idx = settings.actions.firstIndex(where: { $0.id == action.id }) else { return }
                        settings.actions[idx].providerID = newVal.isEmpty ? nil : newVal
                        settings.actions[idx].modelOverride = nil
                        commit()
                    }
                )) {
                    Text("跟随全局默认").tag("")
                    ForEach(settings.providers.filter { $0.isEnabled }) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)

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
                        Text("供应商默认模型").tag("")
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
            }
        }
    }

    private func thinkingBudgetEditor(_ action: AIAction) -> some View {
        HStack(spacing: 6) {
            Text("预算")
                .font(SnapAIUI.Typography.metaText)
                .foregroundStyle(.secondary)
            TextField("tokens", value: Binding<Int>(
                get: { action.thinkingBudget },
                set: { newValue in
                    guard let idx = settings.actions.firstIndex(where: { $0.id == action.id }) else { return }
                    settings.actions[idx].thinkingBudget = AIAction.sanitizedThinkingBudget(newValue)
                    commit()
                }
            ), formatter: NumberFormatter())
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 76)
            Text("tokens")
                .font(SnapAIUI.Typography.metaText)
                .foregroundStyle(.tertiary)
        }
    }

    private func deleteActionRow(_ action: AIAction) -> some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                pendingDeleteAction = action
            } label: {
                Label("删除动作", systemImage: "trash")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(settings.actions.count <= 1 ? Color.secondary : SnapAIUI.StatusColor.error)
            }
            .buttonStyle(.plain)
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
            get: { SettingsPageBinding.actionValue(settings, actionID: id, keyPath: keyPath) },
            set: { newValue in
                guard SettingsPageBinding.setActionValue(settings, actionID: id, keyPath: keyPath, to: newValue) else { return }
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
            ui.hotKeyError = "冲突项在上方「快捷提问浮窗」"
            ui.hotKeyConflictDestination = nil
        }
    }

    private func editorRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(SnapAIUI.Typography.metaText)
                .frame(width: labelWidth, alignment: .trailing)
                .foregroundStyle(.secondary)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func promptEditor(text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(SnapAIUI.Typography.bodyText)
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(height: height)
            .snapAIGlassField(radius: SnapAIUI.controlRadius)
    }
}
