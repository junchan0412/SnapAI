import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ActionSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var navigation: SettingsNavigationModel
    @ObservedObject var ui: AISettingsUI
    let commit: () -> Void
    let applyCommit: (SettingsCommitPolicy) -> Void

    private let labelWidth: CGFloat = 76

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("System Prompt(对所有动作生效)").font(.subheadline.weight(.semibold))
                promptEditor(text: systemPromptBinding, height: 56)
                actionToolbar
                Text("{{text}} = 选中文字;{{lang}} = 目标语言指令(翻译类)。带快捷键的动作可全局触发。")
                    .font(.caption2).foregroundStyle(.secondary)
                hotKeyNotice
                quickPanelHotKeyCard
                ForEach(settings.actions) { action in
                    actionCard(action)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionToolbar: some View {
        HStack {
            Text("动作").font(.headline)
            Spacer()
            Button {
                importActionLibrary()
            } label: {
                Label("导入动作库", systemImage: "square.and.arrow.down")
            }
            Button {
                exportActionLibrary()
            } label: {
                Label("导出动作库", systemImage: "square.and.arrow.up")
            }
            Button {
                restoreDefaultHotKeys()
            } label: {
                Label("恢复默认快捷键", systemImage: "keyboard.badge.ellipsis")
            }
            addActionMenu
        }
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
                    addAction(template.action)
                }
            }
        } label: {
            Label("添加", systemImage: "plus")
        }
    }

    @ViewBuilder
    private var hotKeyNotice: some View {
        if let hotKeyError = ui.hotKeyError {
            HStack(spacing: 8) {
                Label(hotKeyError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                if let destination = ui.hotKeyConflictDestination {
                    Button("查看冲突项") {
                        showHotKeyConflictTarget(destination)
                    }
                    .buttonStyle(.link)
                    .font(.caption2)
                }
            }
        }
    }

    private var quickPanelHotKeyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快捷提问面板")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                Text("全局快捷键")
                    .foregroundStyle(.secondary)
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
                Spacer()
            }
            Text("这个快捷键会直接弹出输入面板,不依赖你先选中文字。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(HotKeyRecorderText.instructions)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .snapAISurface(padding: 9, fillOpacity: SnapAIUI.quietFillOpacity)
    }

    @ViewBuilder
    private func actionCard(_ action: AIAction) -> some View {
        let isExpanded = ui.expandedActionID == action.id
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Toggle("", isOn: bindingForAction(action.id, \.isEnabled))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                Image(systemName: action.icon.isEmpty ? "wand.and.stars" : action.icon)
                    .foregroundStyle(.tint).frame(width: 18)
                Text(action.name).fontWeight(.medium)
                    .foregroundStyle(action.isEnabled ? .primary : .secondary)
                if let hk = action.hotKey {
                    Text(hk.displayString).font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08)).clipShape(Capsule())
                }
                Spacer()
                Button { moveAction(action.id, up: true) } label: { Image(systemName: "chevron.up.circle") }
                    .buttonStyle(.plain).disabled(settings.actions.first?.id == action.id)
                Button { moveAction(action.id, up: false) } label: { Image(systemName: "chevron.down.circle") }
                    .buttonStyle(.plain).disabled(settings.actions.last?.id == action.id)
                Button {
                    ui.expandedActionID = isExpanded ? nil : action.id
                } label: { Image(systemName: isExpanded ? "chevron.up" : "chevron.down") }
                    .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { ui.expandedActionID = isExpanded ? nil : action.id }

            if isExpanded {
                Divider().padding(.vertical, 6)
                actionEditor(action)
            }
        }
        .snapAISurface(padding: 9, fillOpacity: SnapAIUI.quietFillOpacity)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actionEditor(_ action: AIAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            editorRow("名称") {
                TextField("动作名称", text: bindingForAction(action.id, \.name, policy: .deferredSave), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            }
            editorRow("图标") {
                TextField("SF Symbol 名,如 wand.and.stars", text: bindingForAction(action.id, \.icon, policy: .deferredSave), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            }
            editorRow("分组") {
                TextField("分组名(留空=不分组)", text: bindingForAction(action.id, \.group, policy: .deferredSave), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            }
            actionHotKeyEditor(action)
            actionProviderEditor(action)
            Toggle("启用 Thinking / 推理模式", isOn: bindingForAction(action.id, \.thinkingMode))
            if action.thinkingMode {
                thinkingBudgetEditor(action)
            }
            editorRow("Prompt") {
                promptEditor(text: bindingForAction(action.id, \.prompt, policy: .deferredSave), height: 70)
            }
            Toggle("翻译类动作(显示语言切换)", isOn: bindingForAction(action.id, \.isTranslation))
            if action.isTranslation {
                editorRow("目标语言") {
                    Picker("", selection: bindingForAction(action.id, \.targetLanguage)) {
                        ForEach(TargetLanguage.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().frame(width: 200, alignment: .leading)
                }
            }
            Toggle("完成后进入替换确认", isOn: bindingForAction(action.id, \.replaceByDefault))
            Text("启用后会先展示差异预览,确认后才写回原应用。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Toggle("保存到历史记录", isOn: bindingForAction(action.id, \.saveHistory))
            Text("关闭后该动作的结果不会进入历史记录,适合处理隐私敏感内容。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            deleteActionRow(action)
        }
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
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let conflict = hotkeyConflictDetail(for: action) {
                    HStack(spacing: 8) {
                        Label("与「\(conflict.title)」冲突", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Button("查看冲突项") {
                            showHotKeyConflictTarget(conflict.target)
                        }
                        .buttonStyle(.link)
                        .font(.caption2)
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
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func deleteActionRow(_ action: AIAction) -> some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                settings.actions.removeAll { $0.id == action.id }
                if ui.expandedActionID == action.id { ui.expandedActionID = nil }
                commit()
            } label: { Label("删除动作", systemImage: "trash") }
            .disabled(settings.actions.count <= 1)
        }
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
        settings.restoreDefaultHotKeys()
        ui.hotKeyError = nil
        ui.hotKeyConflictDestination = nil
        commit()
    }

    private func importActionLibrary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "导入 SnapAI 动作库"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let data = try? Data(contentsOf: url),
              let imported = try? ActionTemplateLibrary.importedActions(from: data) else { return }
        let installed = ActionTemplateLibrary.installedActions(from: imported,
                                                               existingActions: settings.actions)
        guard !installed.isEmpty else { return }
        settings.actions.append(contentsOf: installed)
        ui.expandedActionID = installed.first?.id
        commit()
    }

    private func exportActionLibrary() {
        guard let data = try? ActionTemplateLibrary.exportBundleData(actions: settings.actions) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SnapAI-Actions.json"
        panel.title = "导出 SnapAI 动作库"
        guard panel.runModal() == .OK,
              let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
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
                .frame(width: labelWidth, alignment: .trailing)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func promptEditor(text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 14))
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(height: height)
            .background(Color.primary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }
}
