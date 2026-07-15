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
            VStack(alignment: .leading, spacing: 12) {
                aiOverviewCard
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
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            Text("将同时清除该供应商保存在钥匙串中的 API Key,此操作不可撤销。")
        }
    }

    private var aiOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("AI 配置").font(.headline)
                Spacer()
                SnapAIStatusPill(title: settings.autoRouteEnabled ? "自动路由" : "固定模型",
                                 systemImage: settings.autoRouteEnabled ? "point.3.connected.trianglepath.dotted" : "cpu",
                                 tint: settings.autoRouteEnabled ? .accentColor : .secondary,
                                 filled: settings.autoRouteEnabled)
                SnapAIStatusPill(title: settings.fallbackEnabled ? "Fallback 开启" : "Fallback 关闭",
                                 systemImage: settings.fallbackEnabled ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath.circle",
                                 tint: settings.fallbackEnabled ? .green : .secondary,
                                 filled: settings.fallbackEnabled)
            }
            currentModelSummaryRow
            routingPolicyRow
            routingDiagnosticsDisclosure
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .snapAISurface(padding: 10, fillOpacity: SnapAIUI.quietFillOpacity)
    }

    private var currentModelSummaryRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(settings.modelSelectionTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(currentModelDetailText)
                    .font(.caption)
                    .foregroundStyle(settings.switchableEntries.isEmpty ? .orange : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                providerMenu
                    .frame(width: 180)
                modelMenu
                    .frame(width: 220)
            }
        }
    }

    private var currentModelDetailText: String {
        guard !settings.switchableEntries.isEmpty else {
            return "还没有可用的供应商和模型。请添加供应商、填写 Key 并获取模型。"
        }
        let provider = settings.activeProvider?.name ?? "未选择供应商"
        let endpoint = settings.activeProvider?.baseURL.isEmpty == false ? (settings.activeProvider?.baseURL ?? "") : "未设置端点"
        return "\(provider) · \(endpoint)"
    }

    private var providerMenu: some View {
        Menu {
            ForEach(settings.providers.filter { $0.isEnabled }) { provider in
                Button {
                    let model = provider.enabledModelNames.first ?? ""
                    settings.activate(providerID: provider.id,
                                      model: model,
                                      recordManualPreference: true)
                    onChange()
                } label: {
                    if provider.id == settings.activeProvider?.id {
                        Label(provider.name, systemImage: "checkmark")
                    } else {
                        Text(provider.name)
                    }
                }
            }
        } label: {
            menuLabel(settings.activeProvider?.name ?? "未选择", icon: "server.rack")
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.bordered)
        .clipped()
    }

    private var modelMenu: some View {
        Menu {
            let names = settings.activeProvider?.enabledModelNames ?? []
            if names.isEmpty {
                Text("无可用模型").foregroundStyle(.secondary)
            }
            ForEach(names, id: \.self) { model in
                Button {
                    settings.activeModel = model
                    commit()
                } label: {
                    if model == settings.model {
                        Label(model, systemImage: "checkmark")
                    } else {
                        Text(model)
                    }
                }
            }
        } label: {
            menuLabel(settings.modelSelectionTitle, icon: "cpu")
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.bordered)
        .clipped()
    }

    private var routingPolicyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                settingsMiniHeader("路由策略", systemImage: "point.3.connected.trianglepath.dotted")
                Spacer()
                if routingHasNoRoutes {
                    SnapAISemanticPill(title: "无可用路由",
                                       systemImage: "exclamationmark.triangle.fill",
                                       tone: .warning)
                } else {
                    SnapAIStatusPill(title: settings.routingPreference.rawValue,
                                     systemImage: "slider.horizontal.3",
                                     tint: .secondary,
                                     filled: false)
                }
            }
            HStack(alignment: .center, spacing: 14) {
                Toggle("自动选择模型", isOn: $settings.autoRouteEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: settings.autoRouteEnabled) { commit() }
                Toggle("失败时切换备用模型", isOn: $settings.fallbackEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: settings.fallbackEnabled) { commit() }
                Spacer(minLength: 12)
                Picker("", selection: $settings.routingPreference) {
                    ForEach(AIRoutingPreference.allCases) { preference in
                        Text(preference.rawValue).tag(preference)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 260)
                .onChange(of: settings.routingPreference) { commit() }
            }
        }
    }

    private var routingDiagnosticsDisclosure: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { ui.showRoutingDiagnostics },
            set: { ui.showRoutingDiagnostics = $0 }
        )) {
            VStack(alignment: .leading, spacing: 6) {
                Text(routingPreviewText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(routingHasNoRoutes ? SnapAIUI.StatusColor.warning : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(settings.routingPreference.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        } label: {
            Label("路由诊断", systemImage: "stethoscope")
                .font(.caption.weight(.semibold))
                .foregroundStyle(routingHasNoRoutes ? SnapAIUI.StatusColor.warning : .secondary)
        }
        .padding(.horizontal, 2)
        .onAppear {
            if routingHasNoRoutes { ui.showRoutingDiagnostics = true }
        }
    }

    private var routingHasNoRoutes: Bool {
        let action = settings.enabledActions.first ?? settings.actions.first ?? AIAction(name: "提问")
        let sampleText = settings.activeContextProfile?.content ?? ""
        let routes = AIRequestRouter.candidates(settings: settings,
                                                action: action,
                                                sourceText: sampleText,
                                                hasImage: false,
                                                routingTextCharacterCount: max(sampleText.count, 1_200))
        return routes.first == nil
    }

    private var routingPreviewText: String {
        let action = settings.enabledActions.first ?? settings.actions.first ?? AIAction(name: "提问")
        let sampleText = settings.activeContextProfile?.content ?? ""
        let routes = AIRequestRouter.candidates(settings: settings,
                                                action: action,
                                                sourceText: sampleText,
                                                hasImage: false,
                                                routingTextCharacterCount: max(sampleText.count, 1_200))
        guard let first = routes.first else {
            return "预览:没有可用路由,请检查供应商、API Key 和模型启用状态。"
        }
        let mode = settings.autoRouteEnabled ? "自动路由" : "当前模型"
        return "预览:\(mode) 会优先尝试 \(first.diagnosticProviderName) / \(first.diagnosticModelName) · \(first.diagnosticReason)"
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

    @ViewBuilder
    private func providerCard(_ provider: AIProvider) -> some View {
        let isExpanded = ui.expandedProviderID == provider.id
        VStack(alignment: .leading, spacing: 0) {
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
                    SnapAIStatusPill(title: "使用中",
                                     systemImage: "checkmark.circle.fill",
                                     tint: .accentColor,
                                     filled: true)
                }
                Spacer()
                Text("\(provider.enabledModelNames.count)/\(provider.models.count) 模型")
                    .font(.caption).foregroundStyle(.secondary)
                Button { moveProvider(provider.id, up: true) } label: { Image(systemName: "chevron.up.circle") }
                    .buttonStyle(.plain)
                    .disabled(settings.providers.first?.id == provider.id)
                    .help("上移")
                    .accessibilityLabel("上移供应商 \(provider.name)")
                Button { moveProvider(provider.id, up: false) } label: { Image(systemName: "chevron.down.circle") }
                    .buttonStyle(.plain)
                    .disabled(settings.providers.last?.id == provider.id)
                    .help("下移")
                    .accessibilityLabel("下移供应商 \(provider.name)")
                Button {
                    ui.expandedProviderID = isExpanded ? nil : provider.id
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "收起供应商 \(provider.name)" : "展开供应商 \(provider.name)")
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { ui.expandedProviderID = isExpanded ? nil : provider.id }

            if isExpanded {
                Divider().padding(.vertical, 6)
                providerEditor(provider)
            }
        }
        .snapAISurface(padding: 9,
                       fillOpacity: SnapAIUI.quietFillOpacity,
                       isSelected: provider.id == settings.activeProviderID)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func providerEditor(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
                TextField("api.openai.com 或 localhost:11434", text: bindingForProvider(provider.id, \.baseURL, policy: .deferredSave), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            }
            editorRow("API Key") {
                SecureField("API Key", text: bindingForProvider(provider.id, \.apiKey, policy: .deferredSave), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            }
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
                } else if provider.apiKey.isEmpty {
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
                .help("获取模型列表")
                .disabled(modelLoader.isLoading(provider.id) || provider.apiKey.isEmpty)
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
            .disabled(tester.isTesting(provider.id) || provider.apiKey.isEmpty)
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

    private func settingsMiniHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
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
