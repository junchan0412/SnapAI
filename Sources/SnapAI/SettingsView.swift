import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var navigation: SettingsNavigationModel
    var onChange: () -> Void   // 设置变更后回调(用于重注册快捷键 + 保存)
    @ObservedObject var pinState: SettingsWindowPinState
    var onPinChange: (Bool) -> Void

    @StateObject private var perm = PermissionState()
    @StateObject private var modelLoader = ModelLoader()
    @StateObject private var ui = AISettingsUI()
    @StateObject private var tester = ConnectionTester()
    let aiLabelWidth: CGFloat = 76
    private var isPinned: Bool { pinState.isPinned }
    private var iCloudSyncStatusText: String {
        guard settings.iCloudSyncEnabled else { return "" }
        let status = settings.iCloudLastSyncStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        let revision = max(0, settings.iCloudRevision)
        let base = status.isEmpty ? "状态: 未同步" : "状态: \(status)"
        return " \(base), revision \(revision)。"
    }

    var body: some View {
        NavigationSplitView {
            settingsSidebar
        } detail: {
            VStack(spacing: 0) {
                settingsHeader
                Divider()
                settingsContentSurface
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, idealWidth: 840, minHeight: 560, idealHeight: 620)
        .onDisappear {
            flushDeferredSave()
        }
    }

    private var settingsSidebar: some View {
        List(selection: Binding<SettingsSection?>(
            get: { navigation.selectedSection },
            set: { selected in
                guard let selected else { return }
                withAnimation(.easeInOut(duration: 0.16)) {
                    navigation.select(selected)
                }
            }
        )) {
            Section("设置") {
                ForEach(SettingsSection.allCases) { section in
                    SettingsSidebarRow(section: section)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 164, ideal: 188, max: 230)
    }

    private var settingsHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: navigation.selectedSection.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(navigation.selectedSection.title)
                    .font(.title3.weight(.semibold))
                Text(navigation.selectedSection.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            pinButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private var pinButton: some View {
        Button {
            let newValue = !pinState.isPinned
            withAnimation(.easeInOut(duration: 0.16)) {
                pinState.isPinned = newValue
            }
            onPinChange(newValue)
        } label: {
            Image(systemName: SettingsWindowPinCommand.statusSystemImage(isPinned: isPinned))
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .scaleEffect(isPinned ? 1.04 : 0.96)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isPinned ? Color.accentColor : .secondary)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isPinned ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isPinned ? Color.accentColor.opacity(0.38) : Color.primary.opacity(0.1), lineWidth: 1)
        }
        .help(isPinned ? "已置顶:点击取消置顶" : "未置顶:点击置顶设置窗口")
        .accessibilityLabel(isPinned ? "设置窗口已置顶" : "设置窗口未置顶")
        .accessibilityValue(SettingsWindowPinCommand.accessibilityValue(isPinned: isPinned))
    }

    private var settingsContentSurface: some View {
        ZStack {
            selectedSectionContent
                .id(navigation.selectedSection.id)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.14), value: navigation.selectedSection)
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch navigation.selectedSection {
        case .ai:
            aiTab
        case .actions:
            actionsTab
        case .history:
            historyTab
        case .general:
            generalTab
        case .permission:
            permissionTab
        }
    }

    // MARK: - AI

    private var aiTab: some View {
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
    }

    // MARK: 当前使用

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
        .padding(9)
        .background(Color.primary.opacity(0.028))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            ForEach(settings.providers.filter { $0.isEnabled }) { p in
                Button {
                    let m = p.enabledModelNames.first ?? ""
                    settings.activate(providerID: p.id,
                                      model: m,
                                      recordManualPreference: true)
                    onChange()
                } label: {
                    if p.id == settings.activeProvider?.id {
                        Label(p.name, systemImage: "checkmark")
                    } else {
                        Text(p.name)
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
            ForEach(names, id: \.self) { m in
                Button {
                    settings.activeModel = m
                    commit()
                } label: {
                    if m == settings.model {
                        Label(m, systemImage: "checkmark")
                    } else {
                        Text(m)
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
                SnapAIStatusPill(title: settings.routingPreference.rawValue,
                                 systemImage: "slider.horizontal.3",
                                 tint: .secondary,
                                 filled: false)
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
        .padding(9)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var routingDiagnosticsDisclosure: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { ui.showRoutingDiagnostics },
            set: { ui.showRoutingDiagnostics = $0 }
        )) {
            VStack(alignment: .leading, spacing: 6) {
                Text(routingPreviewText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
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
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
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
                    SnapAIStatusPill(title: "使用中",
                                     systemImage: "checkmark.circle.fill",
                                     tint: .accentColor,
                                     filled: true)
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
                Label(SensitiveTextSanitizer.sanitizedMessage(err.localizedDescription), systemImage: "xmark.circle.fill")
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
            // #13 超时配置
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

    // MARK: 供应商 / 模型 绑定与增删

    /// 生成对某个供应商某字段的 Binding(按 id 定位,避免下标失效)
    private func bindingForProvider<V>(_ id: String,
                                       _ keyPath: WritableKeyPath<AIProvider, V>,
                                       policy: SettingsCommitPolicy = .fullReload) -> Binding<V> {
        Binding(
            get: {
                (self.settings.providers.first(where: { $0.id == id }) ?? AIProvider())[keyPath: keyPath]
            },
            set: { newValue in
                guard let idx = self.settings.providers.firstIndex(where: { $0.id == id }) else { return }
                self.settings.providers[idx][keyPath: keyPath] = newValue
                self.settings.normalizeActive()
                self.applyCommit(policy)
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
        LocalSecretStore.delete(providerID: id)   // 清除该供应商的本地加密 Key
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

    private var actionsTab: some View {
        ActionSettingsSection(settings: settings,
                              navigation: navigation,
                              ui: ui,
                              commit: commit,
                              applyCommit: applyCommit)
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
                .snapAISurface(padding: 9, fillOpacity: SnapAIUI.quietFillOpacity)
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
            HStack(spacing: 10) {
                Text("保存内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $settings.historyContentStorage) {
                    ForEach(HistoryContentStorage.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 190)
                .onChange(of: settings.historyContentStorage) { commit() }
                Text(settings.historyContentStorage.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
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
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.displayActionName).font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.15)).clipShape(Capsule())
                Text(entry.modelDisplayText).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(entry.dateString).font(.caption2).foregroundStyle(.secondary)
                Button {
                    guard let output = entry.copyableOutputText else { return }
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(output, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain)
                    .disabled(entry.copyableOutputText == nil)
                    .help(entry.copyableOutputText == nil ? "该记录未保存结果" : "复制结果")
            }
            if let source = entry.sourceDisplayText {
                Text(source).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let output = entry.outputDisplayText {
                Text(output).font(.callout)
                    .lineLimit(3)
            } else if entry.sourceDisplayText == nil {
                Text(entry.emptyContentPlaceholder)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .snapAISurface(padding: 9, fillOpacity: SnapAIUI.quietFillOpacity)
    }

    // MARK: - 通用

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                WorkModeSettingsSection(settings: settings) {
                    commit()
                }

                settingsSection("启动与显示") {
                    settingsToggleRow(
                        title: "开机启动",
                        description: "登录系统时自动在菜单栏常驻。",
                        isOn: Binding(
                            get: { perm.launchAtLogin },
                            set: { perm.setLaunchAtLogin($0) }
                        )
                    )
                    compactDivider
                    settingsToggleRow(
                        title: "Dock 图标",
                        description: "关闭后仅保留菜单栏图标；开启时可从 Dock 打开设置。",
                        isOn: Binding(
                            get: { settings.showDockIcon },
                            set: { settings.showDockIcon = $0; commit() }
                        )
                    )
                }

                settingsSection("取词") {
                    settingsToggleRow(
                        title: "优先辅助功能取词",
                        description: "更无感地读取当前选中内容；关闭后统一通过模拟 Command-C 取词。",
                        isOn: Binding(
                            get: { settings.useAXFirst },
                            set: { settings.useAXFirst = $0; commit() }
                        )
                    )
                }

                contextProfilesSection
                privacySection

                settingsSection("同步与动效") {
                    settingsToggleRow(
                        title: "iCloud 配置同步",
                        description: "同步供应商配置、动作和快捷键，不包含 API Key。\(iCloudSyncStatusText)",
                        isOn: Binding(
                            get: { settings.iCloudSyncEnabled },
                            set: { enabled in
                                settings.iCloudSyncEnabled = enabled
                                commit()
                                if enabled { iCloudSync.shared.upload(settings) }
                            }
                        )
                    )
                    compactDivider
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("打字机动画")
                                .font(.callout.weight(.medium))
                            Text("控制 AI 结果逐字显示速度。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 16)
                        Picker("", selection: $settings.typewriterSpeed) {
                            ForEach(TypewriterSpeed.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                        .controlSize(.small)
                        .onChange(of: settings.typewriterSpeed) { commit() }
                    }
                }

                ConfigMigrationSettingsSection(settings: settings, commit: commit)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var privacySection: some View {
        PrivacySettingsSection(settings: settings,
                               ui: ui,
                               commit: commit,
                               applyCommit: applyCommit)
    }

    private var contextProfilesSection: some View {
        ContextProfileSettingsSection(settings: settings,
                                      ui: ui,
                                      commit: commit,
                                      applyCommit: applyCommit)
    }

    // MARK: - 权限

    private var permissionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settingsSection("辅助功能") {
                    HStack(spacing: 10) {
                        Image(systemName: perm.axGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(perm.axGranted ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(perm.axGranted ? "已授予辅助功能权限" : "未授予辅助功能权限")
                                .font(.callout.weight(.medium))
                            Text("SnapAI 需要该权限来读取选中文字并模拟复制按键。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    compactDivider
                    HStack(spacing: 8) {
                        Button("打开系统设置") {
                            NSWorkspace.shared.open(SystemPrivacySettings.accessibilityURL)
                        }
                        Button("重新检测") {
                            perm.refresh(prompt: true)
                        }
                        Spacer()
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func commit() {
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
        onChange()
    }

    private func applyCommit(_ policy: SettingsCommitPolicy) {
        switch policy {
        case .fullReload:
            commit()
        case .saveOnly:
            settings.save()
            iCloudSync.shared.scheduleUpload(settings)
        case .deferredSave:
            scheduleDeferredSave()
        }
    }

    private func scheduleDeferredSave() {
        ui.deferredSaveTask?.cancel()
        ui.deferredSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                settings.save()
                iCloudSync.shared.scheduleUpload(settings)
                ui.deferredSaveTask = nil
            }
        }
    }

    private func flushDeferredSave() {
        ui.deferredSaveTask?.cancel()
        ui.deferredSaveTask = nil
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
    }
}
