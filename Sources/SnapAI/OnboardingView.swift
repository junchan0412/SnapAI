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
                VStack(alignment: .leading, spacing: 28) {
                    introduction
                    VStack(spacing: 0) {
                        setupRow(number: "1", title: "连接你的 AI", detail: "选择云端服务或本地模型，按你的习惯工作。", ready: isAIConfigurationReady) {
                            Button(isAIConfigurationReady ? "管理模型" : "配置模型", action: openSettings)
                        }
                        Divider().padding(.leading, 60)
                        setupRow(number: "2", title: "让选中的文字直接可用", detail: "授予辅助功能权限，便可读取选区、复制和写回。快捷提问无需此权限。", ready: permission.axGranted) {
                            Button(permission.axGranted ? "已授权" : "打开系统设置") {
                                NSWorkspace.shared.open(SystemPrivacySettings.accessibilityURL)
                                permission.refresh(prompt: true)
                            }
                            .disabled(permission.axGranted)
                        }
                    }
                    .background(SnapAIUI.Surface.content, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(SnapAIUI.Surface.border, lineWidth: 1))
                    shortcuts
                }
                .padding(32)
            }
            Divider()
            HStack(spacing: 12) {
                Text(isAIConfigurationReady ? "模型已就绪，随时开始。" : "也可以稍后在菜单栏中完成配置。")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(isAIConfigurationReady ? "开始使用" : "稍后配置", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
        .frame(minWidth: 600, minHeight: 560)
        .background(SnapAIUI.Surface.canvas)
        .onAppear { permission.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission.refresh()
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.tint)
                Text("SnapAI").font(.system(size: 18, weight: .semibold))
            }
            Text("想法，就在手边。")
                .font(.system(size: 32, weight: .semibold))
            Text("选中文字，翻译、润色或提问。\n无需离开正在使用的应用。")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineSpacing(5)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("从一个快捷键开始").font(SnapAIUI.Typography.sectionTitle)
                Spacer()
                if let onTryQuickInput {
                    Button("试试快捷提问", action: onTryQuickInput)
                        .buttonStyle(.link)
                        .disabled(!isAIConfigurationReady)
                        .help(isAIConfigurationReady ? "打开快捷提问" : "配置模型后即可体验")
                }
            }
            HStack(spacing: 12) {
                shortcut("快捷提问", keys: settings.quickPanelHotKey.displayString, icon: "square.and.pencil")
                if let ask = settings.enabledActions.first(where: { $0.name == AIAction.askName }) {
                    shortcut("选区提问", keys: ask.hotKey?.displayString ?? "未设置", icon: "text.bubble")
                }
                if let translate = settings.enabledActions.first(where: { $0.name == AIAction.translateName }) {
                    shortcut("翻译选区", keys: translate.hotKey?.displayString ?? "未设置", icon: "character.bubble")
                }
            }
        }
    }

    private func shortcut(_ title: String, keys: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            SnapAIKeycap(text: keys)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SnapAIUI.Surface.content, in: RoundedRectangle(cornerRadius: 8))
    }

    private func setupRow<Controls: View>(number: String, title: String, detail: String, ready: Bool,
                                          @ViewBuilder controls: () -> Controls) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(ready ? SnapAIUI.StatusColor.success.opacity(0.12) : SnapAIUI.Surface.quiet)
                    .frame(width: 32, height: 32)
                if ready {
                    Image(systemName: "checkmark").foregroundStyle(SnapAIUI.StatusColor.success)
                } else {
                    Text(number).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                controls().controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }
}
