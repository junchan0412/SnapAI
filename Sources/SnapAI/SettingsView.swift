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
                self.errors[providerID] = SensitiveTextSanitizer.sanitizedMessage(error.localizedDescription)
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
    @Published var newRedactionName: String = ""
    @Published var newRedactionPattern: String = ""
    @Published var newRedactionReplacement: String = "[已隐藏]"
    @Published var newContextName: String = ""
    @Published var redactionSample: String = PrivacyFilter.defaultSampleText
    var deferredSaveTask: Task<Void, Never>?
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var selectedSection: SettingsSection = .ai

    func select(_ section: SettingsSection) {
        selectedSection = section
    }
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

private enum SettingsCommitPolicy {
    case fullReload
    case saveOnly
    case deferredSave
}

private struct SettingsSectionPicker: View {
    @Binding var selection: SettingsSection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = section
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: section.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(section.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(width: section.tabWidth, height: 30, alignment: .center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == section ? .primary : .secondary)
                .background {
                    if selection == section {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(nsColor: .selectedControlColor).opacity(0.22))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            }
                    }
                }
                .accessibilityLabel(section.title)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

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
    private let aiLabelWidth: CGFloat = 76
    private var isPinned: Bool { pinState.isPinned }

    var body: some View {
        VStack(spacing: 10) {
            settingsHeader
            settingsContentSurface
        }
        .frame(width: 640, height: 500)
        .padding(12)
        .onDisappear {
            flushDeferredSave()
        }
    }

    private var settingsHeader: some View {
        ZStack {
            SettingsSectionPicker(selection: Binding(
                get: { navigation.selectedSection },
                set: { navigation.selectedSection = $0 }
            ))
            HStack {
                Spacer()
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
        }
        .frame(maxWidth: .infinity)
    }

    private var settingsContentSurface: some View {
        ZStack {
            selectedSectionContent
                .id(navigation.selectedSection.id)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.018))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.easeInOut(duration: 0.18), value: navigation.selectedSection)
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

            HStack(alignment: .top, spacing: 14) {
                currentSelectionColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Divider()
                    .frame(height: 128)
                routeSettingsColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .snapAISurface(padding: 10, fillOpacity: SnapAIUI.quietFillOpacity)
    }

    private var currentSelectionColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            settingsMiniHeader("当前使用", systemImage: "server.rack")
            HStack(spacing: 8) {
                providerMenu
                modelMenu
            }
            .frame(maxWidth: .infinity)
            if settings.switchableEntries.isEmpty {
                Text("还没有可用的「供应商 + 模型」。请在下方添加供应商、填好 Key 并获取模型。")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(settings.activeProvider?.baseURL.isEmpty == false ? (settings.activeProvider?.baseURL ?? "") : "当前供应商未设置端点")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(minHeight: 112, alignment: .topLeading)
    }

    private var providerMenu: some View {
        Menu {
            ForEach(settings.providers.filter { $0.isEnabled }) { p in
                Button {
                    let m = p.enabledModelNames.first ?? ""
                    settings.activate(providerID: p.id, model: m)
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

    private var routeSettingsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingsMiniHeader("路由策略", systemImage: "point.3.connected.trianglepath.dotted")
            Toggle("自动选择模型", isOn: $settings.autoRouteEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: settings.autoRouteEnabled) { commit() }
            HStack(spacing: 8) {
                Text("偏好")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
                Picker("", selection: $settings.routingPreference) {
                    ForEach(AIRoutingPreference.allCases) { preference in
                        Text(preference.rawValue).tag(preference)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .onChange(of: settings.routingPreference) { commit() }
            }
            .frame(maxWidth: .infinity)
            Toggle("失败时切换备用模型", isOn: $settings.fallbackEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: settings.fallbackEnabled) { commit() }
            Text(settings.routingPreference.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 112, alignment: .topLeading)
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
                Text("(Anthropic 必填,留空用默认)").font(.caption2).foregroundStyle(.secondary)
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
                promptEditor(text: systemPromptBinding, height: 56)

                HStack {
                    Text("动作").font(.headline)
                    Spacer()
                    Menu {
                        Button("空白动作") {
                            addAction(AIAction(name: "新动作", icon: "wand.and.stars",
                                               prompt: "请处理下面的文字:\n\n{{text}}"))
                        }
                        Divider()
                        ForEach(actionTemplates, id: \.name) { template in
                            Button(template.name) {
                                addAction(template)
                            }
                        }
                    } label: {
                        Label("添加", systemImage: "plus")
                    }
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
                }
                .snapAISurface(padding: 9, fillOpacity: SnapAIUI.quietFillOpacity)

                ForEach(settings.actions) { action in
                    actionCard(action)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionTemplates: [AIAction] {
        [
            AIAction(name: "邮件回复", icon: "envelope",
                     group: "写作",
                     prompt: "请根据下面的内容起草一封自然、礼貌、简洁的邮件回复。保留必要事实,语气专业,最后只输出邮件正文:\n\n{{text}}"),
            AIAction(name: "会议纪要", icon: "list.clipboard",
                     group: "总结",
                     prompt: "请把下面的会议内容整理为会议纪要,包含:背景、关键结论、待办事项、负责人/时间(如原文有)。使用清晰的 Markdown:\n\n{{text}}"),
            AIAction(name: "代码审查", icon: "checklist",
                     group: "代码",
                     prompt: "请审查下面的代码或变更,优先指出 bug、回归风险、边界条件和测试缺口。按严重程度排序,给出可执行修改建议:\n\n{{text}}"),
            AIAction(name: "中英双语润色", icon: "character.book.closed",
                     group: "写作",
                     prompt: "请将下面内容润色为自然、专业的中英双语表达。先给中文优化版,再给英文优化版,保持原意:\n\n{{text}}"),
            AIAction(name: "图片理解", icon: "photo",
                     group: "图片",
                     prompt: "请仔细理解图片和随附文字,提取关键信息、可见问题和下一步建议:\n\n{{text}}")
        ]
    }

    private func addAction(_ template: AIAction) {
        var action = template
        action.id = UUID().uuidString
        action.hotKey = nil
        settings.actions.append(action)
        ui.expandedActionID = action.id
        commit()
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
            // #10 分组标签
            editorRow("分组") {
                TextField("分组名(留空=不分组)", text: bindingForAction(action.id, \.group, policy: .deferredSave), onCommit: commit)
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
            if action.thinkingMode {
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
        HotKeyConflictDetector.conflict(for: combo,
                                        actions: settings.actions,
                                        excludingActionID: excludingActionID,
                                        quickPanelHotKey: settings.quickPanelHotKey,
                                        includeQuickPanel: includeQuickPanel)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                workModeSection

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
                        description: "同步供应商配置、动作和快捷键，不包含 API Key。",
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

                settingsSection("配置迁移") {
                    HStack(spacing: 8) {
                        Button("导出配置…") { exportConfig() }
                        Button("导入配置…") { importConfig() }
                        Spacer()
                    }
                    Text("导出为 JSON，包含供应商、动作、快捷键等；API Key 不会被导出。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var workModeSection: some View {
        settingsSection("工作模式") {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: settings.matchingWorkModePreset?.systemImage ?? "slider.horizontal.2.square")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.workModeStatusTitle)
                        .font(.callout.weight(.medium))
                    Text(settings.workModeStatusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
            }

            compactDivider

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 8)], spacing: 8) {
                ForEach(WorkModePreset.allCases) { mode in
                    workModeButton(mode)
                }
            }
        }
    }

    private func workModeButton(_ mode: WorkModePreset) -> some View {
        let isCurrent = settings.matchingWorkModePreset == mode
        return Button {
            settings.applyWorkMode(mode)
            commit()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : mode.systemImage)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.shortTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(mode.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isCurrent ? .accentColor : .secondary)
        .help(mode.summary)
    }

    private var privacySection: some View {
        settingsSection("隐私") {
            settingsToggleRow(
                title: "发送前预览",
                description: "发送前查看最终 Prompt、脱敏命中和附件摘要。",
                isOn: Binding(
                    get: { settings.privacyPreviewEnabled },
                    set: { settings.privacyPreviewEnabled = $0; commit() }
                )
            )
            compactDivider
            settingsToggleRow(
                title: "本地脱敏",
                description: "在请求发出前替换匹配文本，规则只在本机执行。",
                isOn: Binding(
                    get: { settings.redactionEnabled },
                    set: { settings.redactionEnabled = $0; commit() }
                )
            )
            if settings.redactionEnabled {
                compactDivider
                redactionRulesEditor
            }
        }
    }

    private var contextProfilesSection: some View {
        settingsSection("上下文包") {
            HStack {
                Text("将项目背景、术语表和偏好合并进 System Prompt。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $settings.activeContextProfileID) {
                    Text("不使用上下文").tag("")
                    ForEach(settings.contextProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .frame(width: 170)
                .controlSize(.small)
                .onChange(of: settings.activeContextProfileID) { commit() }
            }
            ForEach(settings.contextProfiles) { profile in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Toggle("", isOn: bindingForContextProfile(profile.id, \.isEnabled))
                            .labelsHidden()
                            .controlSize(.small)
                        TextField("名称", text: bindingForContextProfile(profile.id, \.name, policy: .deferredSave), onCommit: commit)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                        if settings.activeContextProfileID == profile.id {
                            Text("使用中")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                        }
                        Button {
                            if settings.activeContextProfileID == profile.id {
                                settings.activeContextProfileID = ""
                            }
                            settings.contextProfiles.removeAll { $0.id == profile.id }
                            commit()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .help("删除上下文包")
                    }
                    TextEditor(text: bindingForContextProfile(profile.id, \.content, policy: .deferredSave))
                        .font(.system(size: 12))
                        .frame(height: 58)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color.primary.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                        }
                }
                .padding(7)
                .background(Color.primary.opacity(0.028))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            HStack(spacing: 8) {
                TextField("新上下文包名称", text: $ui.newContextName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Button {
                    addContextProfile()
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .controlSize(.small)
                .disabled(ui.newContextName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func settingsSection<Content: View>(_ title: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .snapAISurface(padding: 9, fillOpacity: SnapAIUI.quietFillOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsToggleRow(title: String,
                                   description: String,
                                   isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactDivider: some View {
        Divider()
            .opacity(0.55)
    }

    private var redactionRulesEditor: some View {
        let preview = redactionPreview
        let newPatternError = newRedactionPatternError
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(settings.redactionRules) { rule in
                let report = preview.reports.first { $0.ruleID == rule.id }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Toggle("", isOn: bindingForRedactionRule(rule.id, \.isEnabled))
                            .labelsHidden()
                        TextField("名称", text: bindingForRedactionRule(rule.id, \.name, policy: .deferredSave), onCommit: commit)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 82)
                        TextField("正则表达式", text: bindingForRedactionRule(rule.id, \.pattern, policy: .deferredSave), onCommit: commit)
                            .textFieldStyle(.roundedBorder)
                        TextField("替换为", text: bindingForRedactionRule(rule.id, \.replacement, policy: .deferredSave), onCommit: commit)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 86)
                        Button {
                            settings.redactionRules.removeAll { $0.id == rule.id }
                            commit()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .help("删除规则")
                    }
                    Label(report?.statusText ?? "未检测", systemImage: report?.isValid == false ? "exclamationmark.triangle.fill" : "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(report?.isValid == false ? Color.red : Color.secondary)
                }
                .padding(6)
                .background(Color.primary.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            HStack(spacing: 6) {
                TextField("名称", text: $ui.newRedactionName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 82)
                TextField("正则表达式", text: $ui.newRedactionPattern)
                    .textFieldStyle(.roundedBorder)
                TextField("替换为", text: $ui.newRedactionReplacement)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 86)
                Button {
                    addRedactionRule()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!canAddRedactionRule)
                Button("恢复默认") {
                    settings.redactionRules = PrivacyRedactionRule.defaults()
                    commit()
                }
                .font(.caption)
            }
            if let newPatternError {
                Label(newPatternError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Divider().padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("规则测试").font(.caption.weight(.semibold))
                    Spacer()
                    Text("命中 \(preview.totalMatches) 处 · 错误 \(preview.invalidReports.count) 条")
                        .font(.caption2)
                        .foregroundStyle(preview.invalidReports.isEmpty ? Color.secondary : Color.red)
                }
                TextEditor(text: $ui.redactionSample)
                    .font(.system(size: 12))
                    .frame(height: PrivacyFilter.defaultSampleEditorHeight)
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .background(Color.primary.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(preview.output)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity,
                           minHeight: max(58, PrivacyFilter.defaultSampleEditorHeight - 14),
                           alignment: .leading)
                    .padding(7)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .font(.caption)
        .padding(8)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var redactionPreview: PrivacyRedactionPreview {
        PrivacyFilter.preview(text: ui.redactionSample, rules: settings.redactionRules)
    }

    private var newRedactionPatternError: String? {
        let pattern = ui.newRedactionPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return nil }
        return PrivacyFilter.validatePattern(pattern)
    }

    private var canAddRedactionRule: Bool {
        let pattern = ui.newRedactionPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        return !pattern.isEmpty && newRedactionPatternError == nil
    }

    private func bindingForContextProfile<V>(_ id: String,
                                             _ keyPath: WritableKeyPath<ContextProfile, V>,
                                             policy: SettingsCommitPolicy = .fullReload) -> Binding<V> {
        Binding(
            get: {
                (settings.contextProfiles.first(where: { $0.id == id }) ?? ContextProfile(name: "", content: ""))[keyPath: keyPath]
            },
            set: { newValue in
                guard let idx = settings.contextProfiles.firstIndex(where: { $0.id == id }) else { return }
                settings.contextProfiles[idx][keyPath: keyPath] = newValue
                applyCommit(policy)
            }
        )
    }

    private func bindingForRedactionRule<V>(_ id: String,
                                             _ keyPath: WritableKeyPath<PrivacyRedactionRule, V>,
                                             policy: SettingsCommitPolicy = .fullReload) -> Binding<V> {
        Binding(
            get: {
                (settings.redactionRules.first(where: { $0.id == id }) ?? PrivacyRedactionRule(name: "", pattern: "", replacement: ""))[keyPath: keyPath]
            },
            set: { newValue in
                guard let idx = settings.redactionRules.firstIndex(where: { $0.id == id }) else { return }
                settings.redactionRules[idx][keyPath: keyPath] = newValue
                applyCommit(policy)
            }
        )
    }

    private func addRedactionRule() {
        let pattern = ui.newRedactionPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty, PrivacyFilter.validatePattern(pattern) == nil else { return }
        let name = ui.newRedactionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = ui.newRedactionReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.redactionRules.append(PrivacyRedactionRule(
            name: name.isEmpty ? "自定义规则" : name,
            pattern: pattern,
            replacement: replacement.isEmpty ? "[已隐藏]" : replacement
        ))
        ui.newRedactionName = ""
        ui.newRedactionPattern = ""
        ui.newRedactionReplacement = "[已隐藏]"
        commit()
    }

    private func addContextProfile() {
        let name = ui.newContextName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let profile = ContextProfile(name: name, content: "")
        settings.contextProfiles.append(profile)
        settings.activeContextProfileID = profile.id
        ui.newContextName = ""
        commit()
    }

    // MARK: 导入/导出(#13)

    private func exportConfig() {
        guard let exportData = settings.exportConfigurationData() else { return }
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
        imported.normalizeImportedConfiguration()
        // 把导入的值拷贝到当前 settings(逐字段)。始终忽略文件里的明文 Key;
        // 同机重导入时,按 provider id 从 Keychain 回填已存的 Key,避免被清空。
        let providerConfig = AppSettings.importedProviderConfiguration(imported.providers,
                                                                       activeProviderID: imported.activeProviderID,
                                                                       activeModel: imported.activeModel)
        settings.providers = providerConfig.providers
        settings.activeProviderID = providerConfig.activeProviderID
        settings.activeModel = providerConfig.activeModel
        settings.temperature = imported.temperature
        settings.actions = AppSettings.sanitizedImportedActions(imported.actions,
                                                                originalProviders: imported.providers,
                                                                sanitizedProviders: settings.providers)
        settings.askHotKey = imported.askHotKey
        settings.translateHotKey = imported.translateHotKey
        settings.quickPanelHotKey = imported.quickPanelHotKey
        settings.askPrompt = imported.askPrompt
        settings.translatePrompt = imported.translatePrompt
        settings.systemPrompt = imported.systemPrompt
        settings.useAXFirst = imported.useAXFirst
        settings.showDockIcon = imported.showDockIcon
        settings.typewriterSpeed = imported.typewriterSpeed
        settings.autoRouteEnabled = imported.autoRouteEnabled
        settings.fallbackEnabled = imported.fallbackEnabled
        settings.routingPreference = imported.routingPreference
        settings.workModePreset = imported.workModePreset
        settings.privacyPreviewEnabled = imported.privacyPreviewEnabled
        settings.redactionEnabled = imported.redactionEnabled
        settings.redactionRules = imported.redactionRules
        settings.historyContentStorage = imported.historyContentStorage
        settings.contextProfiles = imported.contextProfiles
        settings.activeContextProfileID = imported.activeContextProfileID
        settings.historyLimit = imported.historyLimit
        settings.normalizeActive()
        commit()
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
