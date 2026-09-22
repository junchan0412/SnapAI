import SnapAILogic
import SwiftUI

struct ModelSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: AISettingsUI
    let onChange: () -> Void
    let commit: () -> Void
    let applyCommit: (SettingsCommitPolicy) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SnapAIUI.looseSpacing) {
                aiOverviewCard
                temperatureRow
            }
            .padding(SnapAIUI.edgePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .snapAIScrollEdge()
    }

    private var aiOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("当前工作模型").font(SnapAIUI.Typography.sectionTitle)
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
        .padding(SnapAIUI.compactPadding)
        .snapAIGlassCard()
    }

    private var currentModelSummaryRow: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(SnapAIUI.Surface.selected, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(settings.modelSelectionTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(currentModelDetailText)
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                providerMenu
                modelMenu
            }
        }
    }

    private var currentModelDetailText: String {
        guard !settings.switchableEntries.isEmpty else {
            return "还没有可用的供应商和模型。请添加供应商、填写 Key 并获取模型。"
        }
        let provider = settings.activeProvider?.name ?? "未选择供应商"
        let endpoint = settings.activeProvider?.displayHost ?? "未设置端点"
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("自动路由").font(SnapAIUI.Typography.sectionTitle)
                Spacer()
                Picker("优先偏好", selection: $settings.routingPreference) {
                    ForEach(AIRoutingPreference.allCases) { preference in
                        Text(preference.rawValue).tag(preference)
                    }
                }
                .frame(width: 200)
                .onChange(of: settings.routingPreference) { commit() }
            }
            Toggle("根据动作与内容自动选择模型", isOn: $settings.autoRouteEnabled)
                .onChange(of: settings.autoRouteEnabled) { commit() }
            Toggle("请求失败时尝试备用模型", isOn: $settings.fallbackEnabled)
                .onChange(of: settings.fallbackEnabled) { commit() }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
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

    private var temperatureRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Temperature: \(settings.temperature, specifier: "%.2f")").fontWeight(.semibold)
            Slider(value: $settings.temperature, in: 0...1, step: 0.05) { editing in
                if !editing { commit() }
            }
        }
        .padding(.top, 4)
    }
}
