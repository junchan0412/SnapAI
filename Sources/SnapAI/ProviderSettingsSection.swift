import SnapAILogic
import SwiftUI

struct ProviderSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: AISettingsUI
    @ObservedObject var modelLoader: ModelLoader
    @ObservedObject var tester: ConnectionTester
    let onChange: () -> Void
    let commit: () -> Void
    let applyCommit: (SettingsCommitPolicy) -> Void

    private let labelWidth: CGFloat = 76
    @State private var pendingDeleteProvider: AIProvider?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SnapAIUI.looseSpacing) {
                providerSummaryCard
                HStack {
                    Text("供应商").font(.headline)
                    Spacer()
                    addProviderMenu
                }
                ForEach(settings.providers) { provider in
                    providerCard(provider)
                }
            }
            .padding(SnapAIUI.edgePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .snapAIScrollEdge()
        .confirmationDialog(
            "删除供应商「\(pendingDeleteProvider?.name ?? "")」",
            isPresented: Binding(get: { pendingDeleteProvider != nil },
                                 set: { if !$0 { pendingDeleteProvider = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeleteProvider
        ) { provider in
            Button("删除", role: .destructive) { deleteProvider(provider.id) }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("将同时清除该供应商保存在本地加密存储中的 API Key,此操作不可撤销。")
        }
    }

    private var providerSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("供应商总览").font(SnapAIUI.Typography.sectionTitle)
                Spacer()
                SnapAIStatusPill(title: providerSummaryText,
                                 systemImage: providerSummaryIcon,
                                 tint: allProvidersReady ? .green : SnapAIUI.StatusColor.warning,
                                 filled: allProvidersReady)
            }
            Text(providerSummaryDetail)
                .font(SnapAIUI.Typography.metaText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SnapAIUI.compactPadding)
        .snapAIGlassCard()
    }

    private var allProvidersReady: Bool {
        !settings.providers.isEmpty && settings.providers.allSatisfy(AIRequestRouter.isProviderRequestReady)
    }

    private var providerSummaryText: String {
        let ready = settings.providers.filter(AIRequestRouter.isProviderRequestReady).count
        return "\(ready)/\(settings.providers.count) 可请求"
    }

    private var providerSummaryIcon: String {
        allProvidersReady ? "checkmark.circle.fill" : "exclamationmark.circle"
    }

    private var providerSummaryDetail: String {
        if settings.providers.isEmpty {
            return "还没有供应商。点右上角「添加」选择预设,填写 API Key 后获取模型。"
        }
        let bad = settings.providers.filter { !AIRequestRouter.isProviderRequestReady($0) }
        if bad.isEmpty {
            return "全部供应商就绪。展开卡片可测试连接、拉取模型或调整参数。"
        }
        let first = bad.prefix(2).map { "\($0.name.isEmpty ? "未命名供应商" : $0.name): \(AIRequestRouter.providerReadiness($0).displayText)" }.joined(separator: "；")
        return "待处理: \(first)。展开对应卡片按提示修复。"
    }

    private var addProviderMenu: some View {
        Menu {
            ForEach(AIProvider.Preset.allCases) { preset in
                Button(preset.rawValue) {
                    var provider = AIProvider.preset(preset)
                    if settings.providers.contains(where: { $0.name == provider.name }) {
                        provider.name += " 2"
                    }
                    settings.providers.append(provider)
                    ui.expandedProviderID = provider.id
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

    private func providerCard(_ provider: AIProvider) -> some View {
        let isExpanded = ui.expandedProviderID == provider.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    ui.expandedProviderID = isExpanded ? nil : provider.id
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: provider.isLocalEndpoint ? "desktopcomputer" : "network")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.name.isEmpty ? "未命名供应商" : provider.name)
                                .font(SnapAIUI.Typography.sectionTitle)
                                .foregroundStyle(provider.isEnabled ? Color.primary : Color.secondary)
                                .lineLimit(1)
                            Text("\(provider.enabledModelNames.count) 个启用模型 · \(provider.apiProtocol.rawValue)")
                                .font(SnapAIUI.Typography.metaText)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if provider.id == settings.activeProviderID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("当前供应商")
                        }
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isExpanded ? "收起" : "展开")供应商 \(provider.name)")
                Toggle("启用", isOn: bindingForProvider(provider.id, \.isEnabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("启用供应商 \(provider.name)")
                Menu {
                    Button("上移", systemImage: "arrow.up") { moveProvider(provider.id, up: true) }
                        .disabled(settings.providers.first?.id == provider.id)
                    Button("下移", systemImage: "arrow.down") { moveProvider(provider.id, up: false) }
                        .disabled(settings.providers.last?.id == provider.id)
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24)
                .accessibilityLabel("调整供应商 \(provider.name) 的排序")
            }
            if isExpanded {
                providerEditor(provider).padding(.top, 16)
            }
        }
        .padding(16)
        .snapAIGlassCard()
        .overlay {
            if provider.id == settings.activeProviderID {
                RoundedRectangle(cornerRadius: SnapAIUI.cardRadius, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.34), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func providerEditor(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            connectionGroup(provider)
            providerModelLoaderRow(provider)
            editorRow("") {
                modelList(provider)
            }
            addModelRow(provider)
            DisclosureGroup("高级参数") {
                providerParams(provider)
            }
            .font(.caption)
            providerFooterRow(provider)
        }
    }

    /// 连接分组:名称 / 协议 / 端点 / Key。Anthropic 原生协议额外给出
    /// 端点与鉴权头的即时提示,避免把 OpenAI 兼容端点填给 Anthropic 协议。
    private func connectionGroup(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            editorRow("名称") {
                TextField("供应商名称", text: bindingForProvider(provider.id, \.name, policy: .deferredSave), onCommit: commit)
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
                VStack(alignment: .leading, spacing: 4) {
                    TextField(provider.apiProtocol == .anthropic ? "https://api.anthropic.com/v1" : "api.openai.com 或 localhost:11434",
                              text: bindingForProvider(provider.id, \.baseURL, policy: .deferredSave), onCommit: commit)
                        .textFieldStyle(.roundedBorder)
                    if provider.apiProtocol == .anthropic {
                        Text("Anthropic 原生协议固定使用 https://api.anthropic.com/v1,Key 通过 x-api-key 发送(前后空格会自动忽略)。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            editorRow("API Key") {
                SecureField(provider.apiProtocol == .anthropic ? "sk-ant-…" : "API Key",
                            text: bindingForProvider(provider.id, \.apiKey, policy: .deferredSave), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            }
            readinessHint(provider)
        }
    }

    /// 就绪状态一行:直接复用请求层的 providerReadiness,与真实请求能力一致。
    @ViewBuilder
    private func readinessHint(_ provider: AIProvider) -> some View {
        let readiness = AIRequestRouter.providerReadiness(provider)
        editorRow("状态") {
            HStack(spacing: 6) {
                Image(systemName: readiness.isReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(readiness.isReady ? .green : SnapAIUI.StatusColor.warning)
                Text(readiness.isReady ? "就绪,可测试连接或获取模型" : "\(readiness.displayText): \(AIRequestRouter.providerRecoverySuggestion(provider))")
                    .font(.caption)
                    .foregroundStyle(readiness.isReady ? .secondary : SnapAIUI.StatusColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func providerModelLoaderRow(_ provider: AIProvider) -> some View {
        editorRow("模型") {
            HStack(spacing: 8) {
                if let err = modelLoader.errors[provider.id] {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(SnapAIUI.StatusColor.error)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("请先填写 API Key 后再获取模型")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    modelLoader.load(providerID: provider.id, settings: settings, onChange: onChange)
                } label: {
                    if modelLoader.isLoading(provider.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("获取模型", systemImage: "arrow.clockwise")
                    }
                }
                .controlSize(.small)
                .help(provider.apiProtocol == .anthropic ? "获取模型列表(Anthropic 官方 /v1/models)" : "获取模型列表")
                .disabled(modelLoader.isLoading(provider.id) || provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addModelRow(_ provider: AIProvider) -> some View {
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
                    .accessibilityLabel("为供应商 \(provider.name) 添加模型")
                    .disabled(ui.newModelName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func providerFooterRow(_ provider: AIProvider) -> some View {
        HStack {
            Button {
                tester.test(providerID: provider.id, settings: settings)
            } label: {
                if tester.isTesting(provider.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Label("测试连接", systemImage: "bolt.horizontal")
                }
            }
            .disabled(tester.isTesting(provider.id) || provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            testResultLabel(provider.id)
            Spacer()
            Button(role: .destructive) {
                pendingDeleteProvider = provider
            } label: {
                Label("删除此供应商", systemImage: "trash")
            }
            .disabled(settings.providers.count <= 1)
            .help("删除该供应商(需确认,会同时清除 API Key)")
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
                Label(SensitiveTextSanitizer.sanitizedMessage(err.localizedDescription), systemImage: "xmark.circle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private func providerParams(_ provider: AIProvider) -> some View {
        let tempBinding = Binding<Double>(
            get: { settings.providers.first(where: { $0.id == provider.id })?.temperature ?? -1 },
            set: { newVal in
                guard let idx = settings.providers.firstIndex(where: { $0.id == provider.id }) else { return }
                settings.providers[idx].temperature = newVal < 0
                    ? nil
                    : AppSettings.sanitizedImportedProviderTemperature(newVal)
                commit()
            }
        )
        let hasTemp = provider.temperature != nil
        let maxTokBinding = Binding<String>(
            get: { provider.maxTokens.map(String.init) ?? "" },
            set: { str in
                guard let idx = settings.providers.firstIndex(where: { $0.id == provider.id }) else { return }
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                settings.providers[idx].maxTokens = trimmed.isEmpty
                    ? nil
                    : AppSettings.sanitizedImportedMaxTokens(Int(trimmed))
                commit()
            }
        )
        VStack(alignment: .leading, spacing: 6) {
            Toggle("覆盖 Temperature", isOn: Binding(
                get: { hasTemp },
                set: { on in
                    guard let idx = settings.providers.firstIndex(where: { $0.id == provider.id }) else { return }
                    settings.providers[idx].temperature = on
                        ? AppSettings.sanitizedImportedProviderTemperature(settings.temperature)
                        : nil
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
                Text(provider.apiProtocol == .anthropic ? "(Anthropic 固定使用 max_tokens)" : "(留空用默认)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if provider.apiProtocol == .openAI {
                HStack {
                    Text("输出参数").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: bindingForProvider(provider.id, \.outputTokenParameterMode)) {
                        ForEach(OutputTokenParameterMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 260)
                    Text("OpenAI 兼容服务不一致时可切换。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("超时(秒)").font(.caption).foregroundStyle(.secondary)
                TextField("默认 60", text: Binding(
                    get: { provider.requestTimeout.map { "\($0)" } ?? "" },
                    set: { str in
                        guard let idx = settings.providers.firstIndex(where: { $0.id == provider.id }) else { return }
                        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        settings.providers[idx].requestTimeout = trimmed.isEmpty
                            ? nil
                            : AppSettings.sanitizedImportedRequestTimeout(Double(trimmed))
                        commit()
                    }
                ))
                .textFieldStyle(.roundedBorder).frame(width: 70)
                Text("秒").font(.caption2).foregroundStyle(.secondary)
                Text("流式空闲超过此时长会断开，长思考/慢回复请设大。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                .snapAIGlassCard(radius: 8)
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
            if provider.id == settings.activeProvider?.id && entry.name == settings.model {
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
            .accessibilityLabel("从供应商 \(provider.name) 移除模型 \(entry.name)")
        }
        .padding(.vertical, 4)
    }

    private func bindingForProvider<V>(_ id: String,
                                       _ keyPath: WritableKeyPath<AIProvider, V>,
                                       policy: SettingsCommitPolicy = .fullReload) -> Binding<V> {
        Binding(
            get: {
                (settings.providers.first(where: { $0.id == id }) ?? AIProvider())[keyPath: keyPath]
            },
            set: { newValue in
                guard let idx = settings.providers.firstIndex(where: { $0.id == id }) else { return }
                settings.providers[idx][keyPath: keyPath] = newValue
                settings.normalizeActive()
                applyCommit(policy)
            }
        )
    }

    private func bindingForModel<V>(_ providerID: String,
                                    _ modelName: String,
                                    _ keyPath: WritableKeyPath<AIModelEntry, V>) -> Binding<V> {
        Binding(
            get: {
                guard let provider = settings.providers.first(where: { $0.id == providerID }),
                      let model = provider.models.first(where: { $0.name == modelName }) else {
                    return AIModelEntry(name: "")[keyPath: keyPath]
                }
                return model[keyPath: keyPath]
            },
            set: { newValue in
                guard let providerIndex = settings.providers.firstIndex(where: { $0.id == providerID }),
                      let modelIndex = settings.providers[providerIndex].models.firstIndex(where: { $0.name == modelName }) else {
                    return
                }
                settings.providers[providerIndex].models[modelIndex][keyPath: keyPath] = newValue
                settings.normalizeActive()
                commit()
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
        LocalSecretStore.delete(providerID: id)
        settings.normalizeActive()
        commit()
    }

    private func moveProvider(_ id: String, up: Bool) {
        guard let idx = settings.providers.firstIndex(where: { $0.id == id }) else { return }
        let target = up ? idx - 1 : idx + 1
        guard target >= 0, target < settings.providers.count else { return }
        settings.providers.swapAt(idx, target)
        commit()
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
}
