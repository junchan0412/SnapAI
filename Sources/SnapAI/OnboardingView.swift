import SwiftUI
import SnapAILogic

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    var onFinish: () -> Void
    var openSettings: () -> Void
    var onTryQuickInput: (() -> Void)? = nil

    @StateObject private var permission = PermissionState()

    private var isAIConfigurationReady: Bool {
        guard let provider = settings.activeProvider else { return false }
        return AIRequestRouter.isProviderRequestReady(provider)
            && provider.enabledModelNames.contains(settings.model)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroHeader
                    setupChecklistCard
                    shortcutsGrid
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 20)
            }
            .snapAIScrollEdge()

            SnapAIFormDivider(inset: 0)

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isAIConfigurationReady ? SnapAIUI.StatusColor.success : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(isAIConfigurationReady ? "模型已就绪，随时按下快捷键开始使用。" : "也可稍后从顶部菜单栏图标进入设置。")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isAIConfigurationReady ? "开始使用" : "稍后配置", action: onFinish)
                    .buttonStyle(SnapAIPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 580, minHeight: 520)
        .background(SnapAIVisualEffect(material: .underWindowBackground).allowsHitTesting(false).ignoresSafeArea())
        .onAppear { permission.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission.refresh()
        }
    }

    private var heroHeader: some View {
        HStack(spacing: 16) {
            SnapAIAppIcon(settings: settings, size: 56)
            VStack(alignment: .leading, spacing: 5) {
                Text("欢迎使用 SnapAI")
                    .font(.system(size: 24, weight: .bold))
                Text("在任意应用中选中文字即可提问、翻译或润色写回；也可随时呼出快捷提问条。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var setupChecklistCard: some View {
        SnapAISectionGroup("两步完成初始化") {
            EmptyView()
        } content: {
            setupRow(
                step: "1",
                title: "连接 AI 模型服务",
                detail: "支持 OpenAI、Anthropic、DeepSeek 及 Ollama / LM Studio 本地模型。",
                ready: isAIConfigurationReady
            ) {
                Button(isAIConfigurationReady ? "已就绪 · 管理" : "去配置模型", action: openSettings)
                    .buttonStyle(isAIConfigurationReady
                                 ? AnyOnboardingButtonStyle(SnapAISecondaryButtonStyle(compact: true))
                                 : AnyOnboardingButtonStyle(SnapAIPrimaryButtonStyle(compact: true)))
            }

            SnapAIFormDivider(inset: 52)

            setupRow(
                step: "2",
                title: "授予辅助功能权限",
                detail: "用于跨应用读取选中文字并安全写回；仅用快捷提问时可跳过。",
                ready: permission.axGranted
            ) {
                Button(permission.axGranted ? "已授权" : "打开系统设置") {
                    NSWorkspace.shared.open(SystemPrivacySettings.accessibilityURL)
                    permission.refresh(prompt: true)
                }
                .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                .disabled(permission.axGranted)
            }
        }
    }

    private var shortcutsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("常用全局快捷键")
                    .font(SnapAIUI.Typography.sectionTitle)
                Spacer()
                if let onTryQuickInput {
                    Button("立即体验快捷提问 →", action: onTryQuickInput)
                        .buttonStyle(.link)
                        .font(SnapAIUI.Typography.metaText)
                        .disabled(!isAIConfigurationReady)
                }
            }
            HStack(spacing: 10) {
                shortcutCard("快捷提问条", desc: "直接输入或贴图", keys: settings.quickPanelHotKey.displayString, icon: "sparkles")
                if let ask = settings.enabledActions.first(where: { $0.name == AIAction.askName }) {
                    shortcutCard("选区提问", desc: "解释选中内容", keys: ask.hotKey?.displayString ?? "未设置", icon: "text.bubble")
                }
                if let translate = settings.enabledActions.first(where: { $0.name == AIAction.translateName }) {
                    shortcutCard("选区翻译", desc: "中英自然互译", keys: translate.hotKey?.displayString ?? "未设置", icon: "character.bubble")
                }
            }
        }
    }

    private func shortcutCard(_ title: String, desc: String, keys: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                SnapAIKeycap(text: keys)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .snapAIGlassCard(radius: 9)
    }

    private func setupRow<Controls: View>(step: String,
                                          title: String,
                                          detail: String,
                                          ready: Bool,
                                          @ViewBuilder controls: () -> Controls) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(ready ? SnapAIUI.StatusColor.success.opacity(0.15) : Color.accentColor.opacity(0.12))
                    .frame(width: 26, height: 26)
                if ready {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SnapAIUI.StatusColor.success)
                } else {
                    Text(step)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SnapAIUI.Typography.bodyText.weight(.semibold))
                Text(detail)
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            controls()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct AnyOnboardingButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        _makeBody = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}
