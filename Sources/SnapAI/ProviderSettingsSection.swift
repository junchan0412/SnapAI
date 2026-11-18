import SnapAILogic
import SwiftUI
import UniformTypeIdentifiers

struct ProviderSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: AISettingsUI
    @ObservedObject var modelLoader: ModelLoader
    @ObservedObject var tester: ConnectionTester
    let onChange: () -> Void
    let commit: () -> Void
    let applyCommit: (SettingsCommitPolicy) -> Void
    var embedded: Bool = false

    private let labelWidth: CGFloat = 68
    @State private var pendingDeleteProvider: AIProvider?
    @State private var iconProvider: AIProvider?
    @State private var showIconLibrary = false
    @State private var dropTargetProviderID: String?
    private struct ModelSelection: Identifiable {
        let providerID: String
        let entry: AIModelEntry
        var id: String { providerID + "::" + entry.id }
    }
    @State private var editingModel: ModelSelection?

    var body: some View {
        Group {
            if embedded {
                providerContent
            } else {
                ScrollView {
                    providerContent
                        .padding(SnapAIUI.edgePadding)
                }
                .snapAIScrollEdge()
            }
        }
        .sheet(isPresented: $showIconLibrary) {
            ProviderIconPicker(provider: nil, settings: settings, commit: commit)
        }
        .sheet(item: $iconProvider) { provider in
            ProviderIconPicker(provider: provider, settings: settings, commit: commit)
        }
        .sheet(item: $editingModel) { selection in
            if let provider = settings.providers.first(where: { $0.id == selection.providerID }) {
                ModelMetadataEditor(provider: provider, entry: selection.entry) { metadata in
                    guard SettingsPageBinding.setModelValue(settings,
                                                             providerID: provider.id,
                                                             modelName: selection.entry.name,
                                                             keyPath: \.metadata,
                                                             to: metadata) else { return }
                    commit()
                }
            }
        }
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
            Text("将同时清除该供应商保存在本机加密存储中的 API Key，此操作不可撤销。")
        }
    }

    private var providerContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            providerSummaryCard

            if settings.providers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("尚未配置任何 AI 供应商")
                        .font(SnapAIUI.Typography.sectionTitle)
                    Text("点击右上角「添加供应商」，选择 OpenAI、Anthropic、DeepSeek 或本地 Ollama。")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .snapAIGlassCard()
            } else {
                VStack(spacing: 10) {
                    ForEach(settings.providers) { provider in
                        providerCard(provider)
                            .overlay {
                                RoundedRectangle(cornerRadius: SnapAIUI.cardRadius, style: .continuous)
                                    .stroke(Color.accentColor.opacity(dropTargetProviderID == provider.id ? 0.8 : 0), lineWidth: 2)
                                    .allowsHitTesting(false)
                            }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var providerSummaryCard: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("AI 供应商")
                        .font(SnapAIUI.Typography.sectionTitle)
                    SnapAIStatusPill(title: providerSummaryText,
                                     systemImage: providerSummaryIcon,
                                     tint: allProvidersReady ? SnapAIUI.StatusColor.success : SnapAIUI.StatusColor.warning,
                                     filled: allProvidersReady)
                }
                if let warning = providerSummaryWarning {
                    Text(warning)
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(SnapAIUI.StatusColor.warning)
                        .lineLimit(1)
                } else {
                    Text("拖动左侧手柄可调整优先顺序，点击卡片展开编辑 Key 与模型列表")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                showIconLibrary = true
            } label: {
                Label("图标库", systemImage: "square.grid.2x2")
            }
            .buttonStyle(SnapAISecondaryButtonStyle(compact: true))

            addProviderMenu
        }
        .padding(.horizontal, 2)
    }

    private var allProvidersReady: Bool {
        !settings.providers.isEmpty && settings.providers.allSatisfy(AIRequestRouter.isProviderRequestReady)
    }

    private var providerSummaryText: String {
        let ready = settings.providers.filter(AIRequestRouter.isProviderRequestReady).count
        return "\(ready)/\(settings.providers.count) 就绪"
    }

    private var providerSummaryIcon: String {
        allProvidersReady ? "checkmark.circle.fill" : "exclamationmark.circle"
    }

    private var providerSummaryWarning: String? {
        let bad = settings.providers.filter { $0.isEnabled && !AIRequestRouter.isProviderRequestReady($0) }
        guard !bad.isEmpty else { return nil }
        let items = bad.prefix(2).map {
            "\($0.name.isEmpty ? "未命名" : $0.name)：\(AIRequestRouter.providerReadiness($0).displayText)"
        }.joined(separator: "；")
        return "待完善：\(items)"
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
            Label("添加供应商", systemImage: "plus")
        }
        .buttonStyle(SnapAIPrimaryButtonStyle(compact: true))
        .fixedSize()
    }

    private func providerCard(_ provider: AIProvider) -> some View {
        let isExpanded = ui.expandedProviderID == provider.id
        let readiness = AIRequestRouter.providerReadiness(provider)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SettingsDragHandle(name: provider.name, id: provider.id, contentType: .snapAISettingsProvider)
                Button {
                    ui.expandedProviderID = isExpanded ? nil : provider.id
                } label: {
                    HStack(spacing: 11) {
                        ProviderIconView(provider: provider, size: 28, allowsWebsiteRequest: !settings.prefersLocalModelRoutes)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(provider.name.isEmpty ? "未命名供应商" : provider.name)
                                    .font(SnapAIUI.Typography.bodyText.weight(.semibold))
                                    .foregroundStyle(provider.isEnabled ? Color.primary : Color.secondary)
                                    .lineLimit(1)
                                if provider.id == settings.activeProviderID {
                                    Text("当前默认")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                }
                            }
                            HStack(spacing: 5) {
                                Text("\(provider.enabledModelNames.count) 个启用模型")
                                Text("·")
                                Text(provider.apiProtocol.rawValue)
                                if provider.isEnabled && !readiness.isReady {
                                    Text("·")
                                    Text(readiness.displayText)
                                        .foregroundStyle(SnapAIUI.StatusColor.warning)
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if isExpanded {
                SnapAIFormDivider(inset: 14)
                providerEditor(provider)
                    .padding(14)
            }
        }
        .snapAIGlassCard()
        .overlay {
            if provider.id == settings.activeProviderID {
                RoundedRectangle(cornerRadius: SnapAIUI.cardRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(SettingsReorderDropModifier(
            id: provider.id,
            items: $settings.providers, contentType: .snapAISettingsProvider,
            dropTargetID: $dropTargetProviderID, commit: commit))
    }

    @ViewBuilder
    private func providerEditor(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                editorRow("名称") {
                    HStack(spacing: 8) {
                        TextField("供应商名称", text: bindingForProvider(provider.id, \.name, policy: .deferredSave), onCommit: commit)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            iconProvider = provider
                        } label: {
                            HStack(spacing: 5) {
                                ProviderIconView(provider: provider, size: 16, allowsWebsiteRequest: !settings.prefersLocalModelRoutes)
                                Text("图标…")
                            }
                        }
                        .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                    }
                }
            }

            editorRow("协议") {
                Picker("", selection: bindingForProvider(provider.id, \.apiProtocol)) {
                    ForEach(APIProtocol.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 180, alignment: .leading)
                .onChange(of: provider.apiProtocol) { commit() }
            }

            if !provider.isAppleOnDevice {
                editorRow("端点") {
                    TextField(provider.apiProtocol == .anthropic ? "https://api.anthropic.com/v1" : "https://api.openai.com/v1 或 http://localhost:11434/v1",
                              text: bindingForProvider(provider.id, \.baseURL, policy: .deferredSave), onCommit: commit)
                        .textFieldStyle(.roundedBorder)
                }

                editorRow("API Key") {
                    SecureField(provider.apiProtocol == .anthropic ? "sk-ant-…" : "sk-…（本地服务可填任意非空占位符）",
                                text: bindingForProvider(provider.id, \.apiKey, policy: .deferredSave), onCommit: commit)
                        .textFieldStyle(.roundedBorder)
                }
            }

            readinessHint(provider)

            SnapAIFormDivider(inset: 0)

            providerModelSection(provider)

            DisclosureGroup("高级连接参数") {
                providerParams(provider)
                    .padding(.top, 8)
            }
            .font(SnapAIUI.Typography.metaText)

            SnapAIFormDivider(inset: 0)

            providerFooterRow(provider)
        }
    }

    @ViewBuilder
    private func readinessHint(_ provider: AIProvider) -> some View {
        let readiness = AIRequestRouter.providerReadiness(provider)
        if !readiness.isReady {
            editorRow("状态") {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(SnapAIUI.StatusColor.warning)
                    Text("\(readiness.displayText)：\(AIRequestRouter.providerRecoverySuggestion(provider))")
                        .font(.caption)
                        .foregroundStyle(SnapAIUI.StatusColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func providerModelSection(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("可用模型")
                    .font(SnapAIUI.Typography.metaText.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let err = modelLoader.errors[provider.id] {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(SnapAIUI.StatusColor.error)
                        .lineLimit(1)
                }
                Spacer()
                if !provider.isAppleOnDevice {
                    Button {
                        modelLoader.load(providerID: provider.id, settings: settings, onChange: onChange)
                    } label: {
                        if modelLoader.isLoading(provider.id) {
                            ProgressView().controlSize(.mini)
                        } else {
                            Label("从接口拉取", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                    .disabled(modelLoader.isLoading(provider.id) || provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            modelList(provider)

            if !provider.isAppleOnDevice {
                HStack(spacing: 6) {
                    TextField("手动输入模型 ID（回车添加）", text: $ui.newModelName, onCommit: {
                        addModel(to: provider.id)
                    })
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .lineLimit(1)

                    Button {
                        addModel(to: provider.id)
                    } label: {
                        Label("添加", systemImage: "plus")
                    }
                    .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                    .accessibilityLabel("为供应商 \(provider.name) 添加模型")
                    .disabled(ui.newModelName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func providerFooterRow(_ provider: AIProvider) -> some View {
        HStack(spacing: 10) {
            Button {
                tester.test(providerID: provider.id, settings: settings)
            } label: {
                if tester.isTesting(provider.id) {
                    ProgressView().controlSize(.mini)
                } else {
                    Label("测试连接", systemImage: "bolt.horizontal")
                }
            }
            .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
            .disabled(tester.isTesting(provider.id) || (!provider.isAppleOnDevice && provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

            testResultLabel(provider.id)

            Spacer()

            Button(role: .destructive) {
                pendingDeleteProvider = provider
            } label: {
                Label("删除供应商", systemImage: "trash")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(settings.providers.count <= 1 ? Color.secondary : SnapAIUI.StatusColor.error)
            }
            .buttonStyle(.plain)
            .disabled(settings.providers.count <= 1)
            .help("删除该供应商及其本机加密保存的 API Key")
        }
    }

    @ViewBuilder
    private func testResultLabel(_ id: String) -> some View {
        if let result = tester.results[id] {
            switch result {
            case .success:
                Label("连接正常", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(SnapAIUI.StatusColor.success)
            case .failure(let err):
                Label(SensitiveTextSanitizer.sanitizedMessage(err.localizedDescription), systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(SnapAIUI.StatusColor.error)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
        VStack(alignment: .leading, spacing: 8) {
            Toggle("单独覆盖该供应商的 Temperature", isOn: Binding(
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
                    Text(String(format: "%.2f", provider.temperature ?? 0))
                        .font(.caption)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("最大输出 Tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("默认 2048", text: maxTokBinding)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 84)
                }

                HStack(spacing: 6) {
                    Text("超时（秒）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 72)
                }
            }

            if provider.apiProtocol == .openAI {
                Toggle("流式请求返回实际 Token 用量（stream_options）", isOn: bindingForProvider(provider.id, \.streamUsageEnabled))
                    .font(.caption)
                HStack(spacing: 8) {
                    Text("长度字段名")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: bindingForProvider(provider.id, \.outputTokenParameterMode)) {
                        ForEach(OutputTokenParameterMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 240)
                }
            }
        }
    }

    @ViewBuilder
    private func modelList(_ provider: AIProvider) -> some View {
        if provider.models.isEmpty {
            Text("暂无模型，点击右上角「从接口拉取」或在下方手动添加。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        } else {
            modelRows(provider)
                .frame(maxHeight: provider.models.count > 6 ? 176 : nil)
                .snapAIGlassField(radius: 7)
        }
    }

    private func modelRows(_ provider: AIProvider) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(provider.models) { entry in
                    modelRow(provider, entry)
                    if entry.id != provider.models.last?.id {
                        SnapAIFormDivider(inset: 8)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    private func modelRow(_ provider: AIProvider, _ entry: AIModelEntry) -> some View {
        let isCurrentDefault = provider.id == settings.activeProvider?.id && entry.name == settings.model
        return HStack(spacing: 8) {
            Toggle("", isOn: bindingForModel(provider.id, entry.name, \.enabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)

            Text(entry.name)
                .font(.system(size: 12.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(entry.enabled ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isCurrentDefault {
                Text("当前默认")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SnapAIUI.StatusColor.success)
            } else if entry.enabled && provider.isEnabled {
                Button("设为默认") {
                    settings.activate(providerID: provider.id, model: entry.name, recordManualPreference: true)
                    onChange()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }

            Button {
                editingModel = ModelSelection(providerID: provider.id, entry: entry)
            } label: {
                Image(systemName: entry.metadata.hasCapabilityOverrides ? "slider.horizontal.3" : "info.circle")
                    .foregroundStyle(entry.metadata.hasCapabilityOverrides ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("能力覆盖与单价设置")
            .accessibilityLabel("编辑模型 \(entry.name) 的能力与价格")

            if !provider.isAppleOnDevice {
                Button {
                    removeModel(provider.id, entry.name)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("移除模型")
                .accessibilityLabel("从供应商 \(provider.name) 移除模型 \(entry.name)")
            }
        }
        .padding(.vertical, 5)
    }

    private func bindingForProvider<V>(_ id: String,
                                       _ keyPath: WritableKeyPath<AIProvider, V>,
                                       policy: SettingsCommitPolicy = .fullReload) -> Binding<V> {
        Binding(
            get: { SettingsPageBinding.providerValue(settings, providerID: id, keyPath: keyPath) },
            set: { newValue in
                guard SettingsPageBinding.setProviderValue(settings, providerID: id, keyPath: keyPath, to: newValue) else { return }
                applyCommit(policy)
            }
        )
    }

    private func bindingForModel<V>(_ providerID: String,
                                    _ modelName: String,
                                    _ keyPath: WritableKeyPath<AIModelEntry, V>) -> Binding<V> {
        Binding(
            get: {
                SettingsPageBinding.modelValue(settings,
                                               providerID: providerID,
                                               modelName: modelName,
                                               keyPath: keyPath)
            },
            set: { newValue in
                guard SettingsPageBinding.setModelValue(settings,
                                                        providerID: providerID,
                                                        modelName: modelName,
                                                        keyPath: keyPath,
                                                        to: newValue) else { return }
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

    private func editorRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(SnapAIUI.Typography.metaText)
                .frame(width: labelWidth, alignment: .trailing)
                .foregroundStyle(.secondary)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
