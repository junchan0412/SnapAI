import SwiftUI

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
    @Published var newModelName: String = ""
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onChange: () -> Void   // 设置变更后回调(用于重注册快捷键 + 保存)

    @StateObject private var perm = PermissionState()
    @StateObject private var modelLoader = ModelLoader()
    @StateObject private var ui = AISettingsUI()
    private let aiLabelWidth: CGFloat = 76

    var body: some View {
        TabView {
            aiTab.tabItem { Label("AI 模型", systemImage: "brain") }
            hotkeyTab.tabItem { Label("快捷键", systemImage: "keyboard") }
            promptTab.tabItem { Label("Prompt", systemImage: "text.bubble") }
            generalTab.tabItem { Label("通用", systemImage: "gearshape") }
            permissionTab.tabItem { Label("权限", systemImage: "lock.shield") }
        }
        .frame(width: 520, height: 420)
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

            HStack {
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
        settings.normalizeActive()
        commit()
    }

    // MARK: - 快捷键

    private var hotkeyTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("快捷键")
                        .font(.title3.weight(.semibold))
                    Text("为常用操作设置全局触发方式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("恢复默认") {
                    settings.askHotKey = .askDefault
                    settings.translateHotKey = .translateDefault
                    commit()
                }
                .controlSize(.small)
            }

            VStack(spacing: 10) {
                hotkeyCard(
                    title: "AI 提问",
                    subtitle: "对选中文字提问或解释",
                    icon: "sparkles",
                    tint: .blue,
                    combo: $settings.askHotKey
                )
                hotkeyCard(
                    title: "翻译",
                    subtitle: "在中文与英文之间快速转换",
                    icon: "character.bubble",
                    tint: .teal,
                    combo: $settings.translateHotKey
                )
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Text("点击右侧快捷键后按下新的组合键。至少包含一个修饰键,修改后立即生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(.top, 18)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func hotkeyCard(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        combo: Binding<HotKeyCombo>
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HotKeyRecorder(combo: combo)
                .frame(width: 138, height: 34)
                .onChange(of: combo.wrappedValue) { commit() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Prompt

    private var promptTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("使用 {{text}} 代表选中的文字。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("System Prompt").font(.subheadline.weight(.semibold))
            promptEditor(text: $settings.systemPrompt, height: 74)

            Text("提问模板").font(.subheadline.weight(.semibold))
            promptEditor(text: $settings.askPrompt, height: 86)

            Text("翻译模板").font(.subheadline.weight(.semibold))
            promptEditor(text: $settings.translatePrompt, height: 86)

            Button("保存") { commit() }
                .controlSize(.large)

            Spacer(minLength: 0)
        }
        .padding(.top, 18)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

            Picker("打字机动画", selection: $settings.typewriterSpeed) {
                ForEach(TypewriterSpeed.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.typewriterSpeed) { commit() }
            Text("控制 AI 结果逐字显示的速度。选「关闭」则整段一次性显示。")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        onChange()
    }
}
