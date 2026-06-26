import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 追踪设置界面里的运行时状态(辅助功能权限、开机自启)。
/// 这里用 ObservableObject 而非 @State,以兼容仅装了 Command Line Tools
/// 的环境(其缺少 SwiftUI 的 @State 宏插件)。
final class PermissionState: ObservableObject {
    @Published var axGranted: Bool = TextCapture.hasAccessibilityPermission()
    @Published var launchAtLogin: Bool = LoginItem.isEnabled

    func refresh(prompt: Bool = false) {
        axGranted = TextCapture.hasAccessibilityPermission(prompt: prompt)
        launchAtLogin = LoginItem.isEnabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        LoginItem.setEnabled(on)
        // 以系统实际状态为准,避免设置失败时 UI 与真实状态不一致
        launchAtLogin = LoginItem.isEnabled
    }
}

/// 负责为某个供应商拉取可用模型列表。用 ObservableObject 以兼容 CLT 环境(无 @State 宏)。
@MainActor
final class ModelLoader: ObservableObject {
    /// 正在加载的供应商 id(用于在对应行显示菊花)
    @Published var loadingProviderID: String?
    /// 各供应商最近一次拉取的错误信息
    @Published var errors: [String: String] = [:]

    func isLoading(_ providerID: String) -> Bool { loadingProviderID == providerID }

    /// 拉取指定供应商的模型,合并进 settings 并保存。完成后回调以刷新 UI。
    func load(providerID: String, settings: AppSettings, onChange: @escaping () -> Void) {
        guard loadingProviderID == nil else { return }
        guard let idx = settings.providers.firstIndex(where: { $0.id == providerID }) else { return }
        loadingProviderID = providerID
        errors[providerID] = nil

        // 用该供应商构造一个临时的“激活态”,复用 AIClient.listModels
        let probe = AppSettings()
        probe.providers = [settings.providers[idx]]
        probe.activeProviderID = settings.providers[idx].id
        let client = AIClient(settings: probe)

        Task {
            do {
                let list = try await client.listModels()
                if let i = settings.providers.firstIndex(where: { $0.id == providerID }) {
                    settings.providers[i].mergeModels(list)
                    settings.normalizeActive()
                    settings.save()
                    onChange()
                }
            } catch {
                self.errors[providerID] = error.localizedDescription
            }
            self.loadingProviderID = nil
        }
    }
}

/// AI 设置界面的本地 UI 状态(展开的供应商、添加菜单等)。用 ObservableObject 兼容 CLT。
@MainActor
final class AISettingsUI: ObservableObject {
    @Published var expandedProviderID: String?
    @Published var expandedActionID: String?
    @Published var newModelName: String = ""
    @Published var hotKeyError: String?
}

/// 供应商连接测试状态(#2)
@MainActor
final class ConnectionTester: ObservableObject {
    @Published var testingProviderID: String?
    @Published var results: [String: Result<Void, Error>] = [:]

    func isTesting(_ id: String) -> Bool { testingProviderID == id }

    func test(providerID: String, settings: AppSettings) {
        guard testingProviderID == nil,
              let idx = settings.providers.firstIndex(where: { $0.id == providerID }) else { return }
        testingProviderID = providerID
        results[providerID] = nil
        let probe = AppSettings()
        probe.providers = [settings.providers[idx]]
        probe.activeProviderID = settings.providers[idx].id
        probe.activeModel = settings.providers[idx].enabledModelNames.first ?? ""
        let client = AIClient(settings: probe)
        Task {
            do {
                try await client.testConnection()
                self.results[providerID] = .success(())
            } catch {
                self.results[providerID] = .failure(error)
            }
            self.testingProviderID = nil
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onChange: () -> Void   // 设置变更后回调(用于重注册快捷键 + 保存)

    @StateObject private var perm = PermissionState()
    @StateObject private var modelLoader = ModelLoader()
    @StateObject private var ui = AISettingsUI()
    @StateObject private var tester = ConnectionTester()
    private let aiLabelWidth: CGFloat = 76

    var body: some View {
        TabView {
            aiTab.tabItem { Label("AI 模型", systemImage: "brain") }
            actionsTab.tabItem { Label("动作", systemImage: "wand.and.stars") }
            historyTab.tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
            generalTab.tabItem { Label("通用", systemImage: "gearshape") }
            permissionTab.tabItem { Label("权限", systemImage: "lock.shield") }
        }
        .frame(width: 560, height: 460)
        .padding()
    }

    // MARK: - AI

    private var aiTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                currentSelectionCard
                Divider()
                HStack {
                    Text("供应商").font(.headline)
                    Spacer()
                    addProviderMenu
                }
                ForEach(settings.providers) { provider in
                    providerCard(provider)
                }
                temperatureRow
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 当前使用

    private var currentSelectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前使用").font(.headline)
            HStack(spacing: 8) {
                // 供应商选择
                Menu {
                    ForEach(settings.providers.filter { $0.isEnabled }) { p in
                        Button {
                            let m = p.enabledModelNames.first ?? ""
                            settings.activate(providerID: p.id, model: m)
                            onChange()
                        } label: {
                            if p.id == settings.activeProviderID {
                                Label(p.name, systemImage: "checkmark")
                            } else { Text(p.name) }
                        }
                    }
                } label: {
                    menuLabel(settings.activeProvider?.name ?? "未选择", icon: "server.rack")
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .clipped()

                // 模型选择(当前供应商下启用的模型)
                Menu {
                    let names = settings.activeProvider?.enabledModelNames ?? []
                    if names.isEmpty {
                        Text("无可用模型").foregroundStyle(.secondary)
                    }
                    ForEach(names, id: \.self) { m in
                        Button {
                            settings.activeModel = m
                            commit()
                        } label: {
                            if m == settings.activeModel {
                                Label(m, systemImage: "checkmark")
                            } else { Text(m) }
                        }
                    }
                } label: {
                    menuLabel(settings.activeModel.isEmpty ? "选择模型" : settings.activeModel, icon: "cpu")
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .clipped()
            }
            if settings.switchableEntries.isEmpty {
                Text("还没有可用的「供应商 + 模型」。请在下方添加供应商、填好 Key 并获取模型。")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func menuLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        .clipped()
    }

    // MARK: 添加供应商

    private var addProviderMenu: some View {
        Menu {
            ForEach(AIProvider.Preset.allCases) { preset in
                Button(preset.rawValue) {
                    var p = AIProvider.preset(preset)
                    // 避免重名
                    if settings.providers.contains(where: { $0.name == p.name }) {
                        p.name += " 2"
                    }
                    settings.providers.append(p)
                    ui.expandedProviderID = p.id
                    settings.normalizeActive()
                    commit()
                }
            }
        } label: {
            Label("添加", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: 单个供应商卡片

    @ViewBuilder
    private func providerCard(_ provider: AIProvider) -> some View {
        let isExpanded = ui.expandedProviderID == provider.id
        VStack(alignment: .leading, spacing: 0) {
            // 头部:启用开关 + 名称 + 展开/删除
            HStack(spacing: 8) {
                Toggle("", isOn: bindingForProvider(provider.id, \.isEnabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("启用 / 关闭该供应商")

                Text(provider.name.isEmpty ? "(未命名)" : provider.name)
                    .fontWeight(.medium)
                    .foregroundStyle(provider.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if provider.id == settings.activeProviderID {
                    Text("使用中").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }
                Spacer()
                Text("\(provider.enabledModelNames.count)/\(provider.models.count) 模型")
                    .font(.caption).foregroundStyle(.secondary)
                // 排序(#11)
                Button {
                    moveProvider(provider.id, up: true)
                } label: { Image(systemName: "chevron.up.circle") }
                    .buttonStyle(.plain)
                    .disabled(settings.providers.first?.id == provider.id)
                    .help("上移")
                Button {
                    moveProvider(provider.id, up: false)
                } label: { Image(systemName: "chevron.down.circle") }
                    .buttonStyle(.plain)
                    .disabled(settings.providers.last?.id == provider.id)
                    .help("下移")
                Button {
                    ui.expandedProviderID = isExpanded ? nil : provider.id
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { ui.expandedProviderID = isExpanded ? nil : provider.id }

            if isExpanded {
                Divider().padding(.vertical, 6)
                providerEditor(provider)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(provider.id == settings.activeProviderID ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func providerEditor(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            editorRow("名称") {
                TextField("供应商名称", text: bindingForProvider(provider.id, \.name), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            }
            editorRow("协议") {
                Picker("", selection: bindingForProvider(provider.id, \.apiProtocol)) {
                    ForEach(APIProtocol.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 180, alignment: .leading)
                .onChange(of: provider.apiProtocol) { commit() }
            }
            editorRow("端点") {
                TextField("api.openai.com 或 localhost:11434", text: bindingForProvider(provider.id, \.baseURL), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            }
            editorRow("API Key") {
                SecureField("API Key", text: bindingForProvider(provider.id, \.apiKey), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            }

            // 模型管理
            editorRow("模型") {
                HStack(spacing: 8) {
                    if let err = modelLoader.errors[provider.id] {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button {
                        modelLoader.load(providerID: provider.id, settings: settings, onChange: onChange)
                    } label: {
                        if modelLoader.isLoading(provider.id) {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(width: 30, height: 26)
                    .help("获取模型列表")
                    .disabled(modelLoader.isLoading(provider.id) || provider.apiKey.isEmpty)
                }
            }

            editorRow("") {
                modelList(provider)
            }

            // 手动添加模型
            editorRow("添加") {
                HStack(spacing: 6) {
                    TextField("手动添加模型名,回车确认", text: $ui.newModelName, onCommit: {
                        addModel(to: provider.id)
                    })
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    Button { addModel(to: provider.id) } label: { Image(systemName: "plus") }
                        .frame(width: 30, height: 26)
                        .help("添加模型")
                        .disabled(ui.newModelName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            DisclosureGroup("高级参数") {
                providerParams(provider)
            }
            .font(.caption)

            HStack {
                // 连接测试(#2)
                Button {
                    tester.test(providerID: provider.id, settings: settings)
                } label: {
                    if tester.isTesting(provider.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("测试连接", systemImage: "bolt.horizontal")
                    }
                }
                .disabled(tester.isTesting(provider.id) || provider.apiKey.isEmpty)
                testResultLabel(provider.id)
                Spacer()
                Button(role: .destructive) {
                    deleteProvider(provider.id)
                } label: {
                    Label("删除此供应商", systemImage: "trash")
                }
                .disabled(settings.providers.count <= 1)
            }
        }
    }

    @ViewBuilder
    private func testResultLabel(_ id: String) -> some View {
        if let result = tester.results[id] {
            switch result {
            case .success:
                Label("连接成功", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            case .failure(let err):
                Label(err.localizedDescription, systemImage: "xmark.circle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }

    /// 每供应商可选的 temperature / max_tokens 覆盖(#12)
    @ViewBuilder
    private func providerParams(_ provider: AIProvider) -> some View {
        let tempBinding = Binding<Double>(
            get: { settings.providers.first(where: { $0.id == provider.id })?.temperature ?? -1 },
            set: { newVal in
                guard let idx = settings.providers.firstIndex(where: { $0.id == provider.id }) else { return }
                settings.providers[idx].temperature = newVal < 0 ? nil : newVal
                commit()
            }
        )
        let hasTemp = provider.temperature != nil
        let maxTokBinding = Binding<String>(
            get: { provider.maxTokens.map(String.init) ?? "" },
            set: { str in
                guard let idx = settings.providers.firstIndex(where: { $0.id == provider.id }) else { return }
                settings.providers[idx].maxTokens = Int(str.trimmingCharacters(in: .whitespaces))
                commit()
            }
        )
        VStack(alignment: .leading, spacing: 6) {
            Toggle("覆盖 Temperature", isOn: Binding(
                get: { hasTemp },
                set: { on in
                    guard let idx = settings.providers.firstIndex(where: { $0.id == provider.id }) else { return }
                    settings.providers[idx].temperature = on ? settings.temperature : nil
                    commit()
                }
            ))
            .font(.caption)
            if hasTemp {
                HStack {
                    Slider(value: tempBinding, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", provider.temperature ?? 0)).font(.caption).monospacedDigit()
                }
            }
            HStack {
                Text("Max tokens").font(.caption).foregroundStyle(.secondary)
                TextField("默认 2048", text: maxTokBinding)
                    .textFieldStyle(.roundedBorder).frame(width: 90)
                Text("(Anthropic 必填,留空用默认)").font(.caption2).foregroundStyle(.secondary)
            }
            // #13 超时配置
            HStack {
                Text("超时(秒)").font(.caption).foregroundStyle(.secondary)
                TextField("默认 60", text: Binding(
                    get: { provider.requestTimeout.map { "\($0)" } ?? "" },
                    set: { str in
                        guard let idx = settings.providers.firstIndex(where: { $0.id == provider.id }) else { return }
                        settings.providers[idx].requestTimeout = Double(str.trimmingCharacters(in: .whitespaces))
                        commit()
                    }
                ))
                .textFieldStyle(.roundedBorder).frame(width: 70)
                Text("秒").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func modelList(_ provider: AIProvider) -> some View {
        if provider.models.isEmpty {
            Text("暂无模型。点「获取模型」自动拉取,或在下方手动添加。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            modelRows(provider)
                .frame(maxHeight: provider.models.count > 6 ? 168 : nil)
                .background(Color.primary.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func modelRows(_ provider: AIProvider) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(provider.models) { entry in
                    modelRow(provider, entry)
                    if entry.id != provider.models.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func modelRow(_ provider: AIProvider, _ entry: AIModelEntry) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: bindingForModel(provider.id, entry.name, \.enabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(entry.enabled ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if provider.id == settings.activeProviderID && entry.name == settings.activeModel {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            Button {
                removeModel(provider.id, entry.name)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("移除模型")
        }
        .padding(.vertical, 4)
    }

    private var temperatureRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Temperature: \(settings.temperature, specifier: "%.2f")").fontWeight(.semibold)
            Slider(value: $settings.temperature, in: 0...1, step: 0.05) { editing in
                if !editing { commit() }
            }
        }
        .padding(.top, 4)
    }

    private func editorRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .frame(width: aiLabelWidth, alignment: .trailing)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 供应商 / 模型 绑定与增删

    /// 生成对某个供应商某字段的 Binding(按 id 定位,避免下标失效)
    private func bindingForProvider<V>(_ id: String, _ keyPath: WritableKeyPath<AIProvider, V>) -> Binding<V> {
        Binding(
            get: {
                (self.settings.providers.first(where: { $0.id == id }) ?? AIProvider())[keyPath: keyPath]
            },
            set: { newValue in
                guard let idx = self.settings.providers.firstIndex(where: { $0.id == id }) else { return }
                self.settings.providers[idx][keyPath: keyPath] = newValue
                self.settings.normalizeActive()
                self.commit()
            }
        )
    }

    /// 生成对某供应商下某模型条目字段的 Binding
    private func bindingForModel<V>(_ providerID: String, _ modelName: String, _ keyPath: WritableKeyPath<AIModelEntry, V>) -> Binding<V> {
        Binding(
            get: {
                guard let p = self.settings.providers.first(where: { $0.id == providerID }),
                      let m = p.models.first(where: { $0.name == modelName }) else { return AIModelEntry(name: "")[keyPath: keyPath] }
                return m[keyPath: keyPath]
            },
            set: { newValue in
                guard let pi = self.settings.providers.firstIndex(where: { $0.id == providerID }),
                      let mi = self.settings.providers[pi].models.firstIndex(where: { $0.name == modelName }) else { return }
                self.settings.providers[pi].models[mi][keyPath: keyPath] = newValue
                self.settings.normalizeActive()
                self.commit()
            }
        )
    }

    private func addModel(to providerID: String) {
        let name = ui.newModelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              let idx = settings.providers.firstIndex(where: { $0.id == providerID }) else { return }
        if !settings.providers[idx].models.contains(where: { $0.name == name }) {
            settings.providers[idx].models.append(AIModelEntry(name: name, enabled: true))
        }
        ui.newModelName = ""
        settings.normalizeActive()
        commit()
    }

    private func removeModel(_ providerID: String, _ name: String) {
        guard let idx = settings.providers.firstIndex(where: { $0.id == providerID }) else { return }
        settings.providers[idx].models.removeAll { $0.name == name }
        settings.normalizeActive()
        commit()
    }

    private func deleteProvider(_ id: String) {
        settings.providers.removeAll { $0.id == id }
        if ui.expandedProviderID == id { ui.expandedProviderID = nil }
        Keychain.delete(providerID: id)   // 清除该供应商在 Keychain 的 Key
        settings.normalizeActive()
        commit()
    }

    /// 上移/下移供应商(#11)
    private func moveProvider(_ id: String, up: Bool) {
        guard let idx = settings.providers.firstIndex(where: { $0.id == id }) else { return }
        let target = up ? idx - 1 : idx + 1
        guard target >= 0, target < settings.providers.count else { return }
        settings.providers.swapAt(idx, target)
        commit()
    }

    // MARK: - 动作(#4 / #7)

    private var actionsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("System Prompt(对所有动作生效)").font(.subheadline.weight(.semibold))
                promptEditor(text: $settings.systemPrompt, height: 56)
                    .onChange(of: settings.systemPrompt) { commit() }

                HStack {
                    Text("动作").font(.headline)
                    Spacer()
                    Button {
                        let a = AIAction(name: "新动作", icon: "wand.and.stars",
                                         prompt: "请处理下面的文字:\n\n{{text}}")
                        settings.actions.append(a)
                        ui.expandedActionID = a.id
                        commit()
                    } label: { Label("添加", systemImage: "plus") }
                    .menuStyle(.borderlessButton)
                }
                Text("{{text}} = 选中文字;{{lang}} = 目标语言指令(翻译类)。带快捷键的动作可全局触发。")
                    .font(.caption2).foregroundStyle(.secondary)
                if let hotKeyError = ui.hotKeyError {
                    Label(hotKeyError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("快捷提问面板")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 12) {
                        Text("全局快捷键")
                            .foregroundStyle(.secondary)
                        HotKeyRecorder(combo: Binding(
                            get: { settings.quickPanelHotKey },
                            set: { newVal in
                                if let conflict = hotKeyConflict(for: newVal, excludingActionID: nil, includeQuickPanel: false) {
                                    ui.hotKeyError = "快捷提问面板与「\(conflict)」冲突,未保存"
                                    return
                                }
                                ui.hotKeyError = nil
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
                }
                .padding(12)
                .background(Color.primary.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                ForEach(settings.actions) { action in
                    actionCard(action)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func actionEditor(_ action: AIAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            editorRow("名称") {
                TextField("动作名称", text: bindingForAction(action.id, \.name), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            }
            editorRow("图标") {
                TextField("SF Symbol 名,如 wand.and.stars", text: bindingForAction(action.id, \.icon), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            }
            // #10 分组标签
            editorRow("分组") {
                TextField("分组名(留空=不分组)", text: bindingForAction(action.id, \.group), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            }
            editorRow("快捷键") {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        HotKeyRecorder(combo: Binding(
                            get: { action.hotKey ?? HotKeyCombo(keyCode: 0, modifiers: 0) },
                            set: { newVal in
                                guard let idx = settings.actions.firstIndex(where: { $0.id == action.id }) else { return }
                                if newVal.modifiers != 0,
                                   let conflict = hotKeyConflict(for: newVal, excludingActionID: action.id, includeQuickPanel: true) {
                                    ui.hotKeyError = "动作「\(action.name)」与「\(conflict)」冲突,未保存"
                                    return
                                }
                                ui.hotKeyError = nil
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
                    // #6 冲突检测
                    if let conflict = hotkeyConflict(for: action) {
                        Label("与「\(conflict)」冲突", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            // #1 per-action 供应商
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
                        // 显示该供应商下全部模型(不限已启用),便于为动作单独指定
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
            // #2 thinking 模式
            Toggle("启用 Thinking / 推理模式", isOn: bindingForAction(action.id, \.thinkingMode))
                .onChange(of: action.thinkingMode) { commit() }
            if action.thinkingMode {
                editorRow("思考预算") {
                    HStack {
                        TextField("tokens", value: bindingForAction(action.id, \.thinkingBudget), formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                        Text("tokens(Anthropic 专用,建议 4000–16000)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            editorRow("Prompt") {
                promptEditor(text: bindingForAction(action.id, \.prompt), height: 70)
            }
            Toggle("翻译类动作(显示语言切换)", isOn: bindingForAction(action.id, \.isTranslation))
                .onChange(of: action.isTranslation) { commit() }
            if action.isTranslation {
                editorRow("目标语言") {
                    Picker("", selection: bindingForAction(action.id, \.targetLanguage)) {
                        ForEach(TargetLanguage.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().frame(width: 200, alignment: .leading)
                    .onChange(of: action.targetLanguage) { commit() }
                }
            }
            Toggle("完成后默认替换原文", isOn: bindingForAction(action.id, \.replaceByDefault))
                .onChange(of: action.replaceByDefault) { commit() }

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
    }

    private func bindingForAction<V>(_ id: String, _ keyPath: WritableKeyPath<AIAction, V>) -> Binding<V> {
        Binding(
            get: { (settings.actions.first(where: { $0.id == id }) ?? AIAction())[keyPath: keyPath] },
            set: { newValue in
                guard let idx = settings.actions.firstIndex(where: { $0.id == id }) else { return }
                settings.actions[idx][keyPath: keyPath] = newValue
                commit()
            }
        )
    }

    private func moveAction(_ id: String, up: Bool) {
        guard let idx = settings.actions.firstIndex(where: { $0.id == id }) else { return }
        let target = up ? idx - 1 : idx + 1
        guard target >= 0, target < settings.actions.count else { return }
        settings.actions.swapAt(idx, target)
        commit()
    }

    /// #6 检测快捷键冲突:返回冲突的动作名或"快捷提问"
    private func hotkeyConflict(for action: AIAction) -> String? {
        guard let hk = action.hotKey, hk.modifiers != 0 else { return nil }
        return hotKeyConflict(for: hk, excludingActionID: action.id, includeQuickPanel: true)
    }

    private func hotKeyConflict(for combo: HotKeyCombo,
                                excludingActionID: String?,
                                includeQuickPanel: Bool) -> String? {
        guard combo.modifiers != 0 else { return nil }
        for other in settings.actions where other.id != excludingActionID {
            if other.hotKey == combo { return other.name }
        }
        if includeQuickPanel && settings.quickPanelHotKey == combo {
            return "快捷提问面板"
        }
        return nil
    }

    // MARK: - 历史

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            // #11 使用统计
            if !settings.actionUsageCounts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("使用统计").font(.subheadline.weight(.semibold))
                    let sorted = settings.actionUsageCounts.sorted { $0.value > $1.value }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(sorted, id: \.key) { name, count in
                            HStack {
                                Text(name).lineLimit(1)
                                Spacer()
                                Text("\(count) 次").foregroundStyle(.secondary).monospacedDigit()
                            }
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    HStack {
                        Text("共 \(settings.history.count) 条记录").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button("清空统计") {
                            settings.actionUsageCounts = [:]
                            commit()
                        }
                        .font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(10).background(Color.primary.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius: 8))
                Divider()
            }

            HStack {
                Text("历史记录").font(.headline)
                Spacer()
                Stepper("保留 \(settings.historyLimit) 条", value: $settings.historyLimit, in: 0...500, step: 10)
                    .onChange(of: settings.historyLimit) { commit() }
                Button("清空") { settings.clearHistory() }
                    .disabled(settings.history.isEmpty)
            }
            if settings.history.isEmpty {
                Spacer()
                Text("暂无历史记录").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(settings.history) { entry in historyRow(entry) }
                    }
                }
            }
        }
        .padding(.top, 14).padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.actionName).font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.15)).clipShape(Capsule())
                Text("\(entry.provider) / \(entry.model)").font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(entry.dateString).font(.caption2).foregroundStyle(.secondary)
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(entry.output, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).help("复制结果")
            }
            Text(entry.source).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
            Text(entry.output).font(.callout)
                .lineLimit(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    // MARK: - 通用

    private var generalTab: some View {
        Form {
            Toggle("开机时自动启动 SnapAI", isOn: Binding(
                get: { perm.launchAtLogin },
                set: { perm.setLaunchAtLogin($0) }
            ))
            Text("启用后,登录系统时 SnapAI 会自动在菜单栏常驻。")
                .font(.caption).foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            Toggle("在 Dock 显示图标", isOn: $settings.showDockIcon)
                .onChange(of: settings.showDockIcon) { commit() }
            Text("关闭后仅保留菜单栏图标。开启时可从 Dock 点击图标打开设置。")
                .font(.caption).foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            Toggle("优先使用辅助功能直接取词(更无感)", isOn: $settings.useAXFirst)
                .onChange(of: settings.useAXFirst) { commit() }
            Text("关闭后将统一通过模拟 ⌘C 取词。")
                .font(.caption).foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            Toggle("iCloud 配置同步", isOn: $settings.iCloudSyncEnabled)
                .onChange(of: settings.iCloudSyncEnabled) {
                    commit()
                    if settings.iCloudSyncEnabled { iCloudSync.shared.upload(settings) }
                }
            Text("将供应商配置、动作和快捷键同步到 iCloud(不含 API Key)。同一 Apple ID 的多台 Mac 共享配置。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 4)

            Picker("打字机动画", selection: $settings.typewriterSpeed) {
                ForEach(TypewriterSpeed.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.typewriterSpeed) { commit() }
            Text("控制 AI 结果逐字显示的速度。选「关闭」则整段一次性显示。")
                .font(.caption).foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            // 配置导入/导出(#13)
            Text("配置迁移").font(.subheadline.weight(.semibold))
            HStack {
                Button("导出配置…") { exportConfig() }
                Button("导入配置…") { importConfig() }
            }
            Text("导出为 JSON(含供应商、动作、快捷键等)。出于安全,API Key 不包含在内,需在新机器重新填写。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 导入/导出(#13)

    private func exportConfig() {
        guard let data = try? JSONEncoder().encode(settings),
              let exportSettings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return }
        exportSettings.history = []
        exportSettings.onboardingDone = true
        guard let exportData = try? JSONEncoder().encode(exportSettings) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SnapAI-config.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? exportData.write(to: url)
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let imported = try? JSONDecoder().decode(AppSettings.self, from: data) else { return }
        // 把导入的值拷贝到当前 settings(逐字段)。导入不含明文 Key:
        // 同机重导入时,按 provider id 从 Keychain 回填已存的 Key,避免被清空。
        var imp = imported.providers
        for i in imp.indices where imp[i].apiKey.isEmpty {
            imp[i].apiKey = Keychain.apiKey(for: imp[i].id)
        }
        settings.providers = imp
        settings.activeProviderID = imported.activeProviderID
        settings.activeModel = imported.activeModel
        settings.temperature = imported.temperature
        settings.actions = imported.actions
        settings.askHotKey = imported.askHotKey
        settings.translateHotKey = imported.translateHotKey
        settings.quickPanelHotKey = imported.quickPanelHotKey
        settings.askPrompt = imported.askPrompt
        settings.translatePrompt = imported.translatePrompt
        settings.systemPrompt = imported.systemPrompt
        settings.useAXFirst = imported.useAXFirst
        settings.showDockIcon = imported.showDockIcon
        settings.typewriterSpeed = imported.typewriterSpeed
        settings.historyLimit = imported.historyLimit
        settings.normalizeActive()
        commit()
    }

    // MARK: - 权限

    private var permissionTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: perm.axGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(perm.axGranted ? .green : .red)
                Text(perm.axGranted ? "已授予辅助功能权限" : "未授予辅助功能权限")
            }

            Text("SnapAI 需要「辅助功能」权限来读取选中文字、模拟复制按键。请在系统设置 → 隐私与安全性 → 辅助功能 中勾选 SnapAI。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("打开系统设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("重新检测") {
                    perm.refresh(prompt: true)
                }
            }
            Spacer()
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commit() {
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
        onChange()
    }
}
