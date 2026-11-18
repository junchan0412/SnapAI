import SnapAILogic
import SwiftUI

struct ModelSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var navigation: SettingsNavigationModel
    @ObservedObject var ui: AISettingsUI
    @ObservedObject var modelLoader: ModelLoader
    @ObservedObject var tester: ConnectionTester
    let onChange: () -> Void
    let commit: () -> Void
    let applyCommit: (SettingsCommitPolicy) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: SnapAIUI.looseSpacing) {
                    aiOverviewCard

                    ProviderSettingsSection(settings: settings,
                                            ui: ui,
                                            modelLoader: modelLoader,
                                            tester: tester,
                                            onChange: onChange,
                                            commit: commit,
                                            applyCommit: applyCommit,
                                            embedded: true)
                        .id("providers-section")

                    usageCard
                }
                .padding(SnapAIUI.edgePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .snapAIScrollEdge()
            .onChange(of: navigation.scrollToProvidersToken) {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("providers-section", anchor: .top)
                }
            }
        }
    }

    private var aiOverviewCard: some View {
        SnapAISectionGroup("默认模型与路由策略") {
            HStack(spacing: 6) {
                SnapAIStatusPill(title: settings.autoRouteEnabled ? "智能路由" : "固定模型",
                                 systemImage: settings.autoRouteEnabled ? "point.3.connected.trianglepath.dotted" : "cpu",
                                 tint: settings.autoRouteEnabled ? .accentColor : .secondary,
                                 filled: settings.autoRouteEnabled)
                if settings.fallbackEnabled {
                    SnapAIStatusPill(title: "自动回退开启",
                                     systemImage: "arrow.triangle.2.circlepath",
                                     tint: SnapAIUI.StatusColor.success,
                                     filled: true)
                }
            }
        } content: {
            SnapAISettingRow(
                title: "当前工作模型",
                subtitle: currentModelDetailText,
                icon: "cpu",
                iconTint: .accentColor
            ) {
                HStack(spacing: 8) {
                    providerMenu
                    modelMenu
                }
            }

            SnapAIFormDivider()

            SnapAISettingRow(
                title: "输出随机性 (Temperature)",
                subtitle: "数值越低回答越严谨稳定，越高越富有发散性。",
                icon: "thermometer.medium",
                iconTint: .orange
            ) {
                HStack(spacing: 8) {
                    Slider(value: $settings.temperature, in: 0...1, step: 0.05) { editing in
                        if !editing { commit() }
                    }
                    .frame(width: 140)
                    .accessibilityLabel("Temperature")

                    Text(String(format: "%.2f", settings.temperature))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            SnapAIFormDivider()

            SnapAISettingRow(
                title: "根据动作与内容自动选模",
                subtitle: routingPreviewText,
                icon: "point.3.connected.trianglepath.dotted",
                iconTint: .purple
            ) {
                HStack(spacing: 10) {
                    if settings.autoRouteEnabled {
                        Picker("优先偏好", selection: $settings.routingPreference) {
                            ForEach(AIRoutingPreference.allCases) { preference in
                                Text(preference.rawValue).tag(preference)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 100)
                        .accessibilityLabel("优先偏好")
                        .onChange(of: settings.routingPreference) { commit() }
                    }

                    Toggle("", isOn: $settings.autoRouteEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("根据动作与内容自动选择模型")
                        .onChange(of: settings.autoRouteEnabled) { commit() }
                }
            }

            SnapAIFormDivider()

            SnapAISettingRow(
                title: "请求失败时自动尝试备用模型",
                subtitle: "当首选服务超时或报错时，平滑切换到其他可用供应商。",
                icon: "arrow.triangle.2.circlepath",
                iconTint: .green
            ) {
                Toggle("", isOn: $settings.fallbackEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("请求失败时尝试备用模型")
                    .onChange(of: settings.fallbackEnabled) { commit() }
            }
        }
    }

    private var currentModelDetailText: String {
        guard !settings.switchableEntries.isEmpty else {
            return "请在下方展开或添加供应商，填写 API Key 并启用模型。"
        }
        let provider = settings.activeProvider?.name ?? "未选择供应商"
        let endpoint = settings.activeProvider?.displayHost ?? "默认端点"
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
            menuLabel(settings.activeProvider?.name ?? "选择供应商")
        }
        .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
    }

    private var modelMenu: some View {
        Menu {
            let names = settings.activeProvider?.enabledModelNames ?? []
            if names.isEmpty {
                Text("无可用模型")
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
            menuLabel(settings.modelSelectionTitle)
        }
        .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
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
            return "当前无可用路由，请检查下方供应商与模型启用状态。"
        }
        if settings.autoRouteEnabled {
            return "当前策略（\(settings.routingPreference.rawValue)）优先路由至 \(first.diagnosticProviderName) / \(first.diagnosticModelName)"
        }
        return "开启后按任务复杂度与图片能力自动匹配最佳模型。"
    }

    private func menuLabel(_ text: String) -> some View {
        HStack(spacing: 5) {
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 145, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var usageCard: some View {
        RequestUsageDashboardView(settings: settings)
    }
}
