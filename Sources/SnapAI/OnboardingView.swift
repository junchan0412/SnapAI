import SwiftUI
import SnapAILogic

/// 首次启动引导页:介绍 → 权限 → 配置 → 完成
struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    var onFinish: () -> Void
    var openSettings: () -> Void

    @StateObject private var perm = PermissionState()

    var body: some View {
        VStack(spacing: 0) {
            // 顶部品牌
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("欢迎使用 SnapAI")
                    .font(.title.weight(.bold))
                Text("在任意应用选中文字,一键 AI 提问、翻译、润色")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                stepRow(
                    number: 1,
                    title: "授予辅助功能权限",
                    desc: "用于读取选中文字与模拟复制/粘贴。",
                    done: perm.axGranted
                ) {
                    Button(perm.axGranted ? "已授权" : "去授权") {
                        if !perm.axGranted {
                            NSWorkspace.shared.open(SystemPrivacySettings.accessibilityURL)
                            _ = TextCapture.hasAccessibilityPermission(prompt: true)
                        }
                        perm.refresh(prompt: true)
                    }
                    .disabled(perm.axGranted)
                }

                stepRow(
                    number: 2,
                    title: "配置 AI 供应商",
                    desc: "填入 API Key,获取并启用至少一个模型(支持 OpenAI / DeepSeek / Claude / Ollama 等)。",
                    done: isAIConfigurationReady
                ) {
                    Button("打开设置") { openSettings() }
                }

                stepRow(
                    number: 3,
                    title: "开始使用",
                    desc: "选中文字按 ⌥A 提问、⌥T 翻译;或按 \(settings.quickPanelHotKey.displayString) 快捷提问。",
                    done: false,
                    showCheck: false
                ) { EmptyView() }
            }
            .padding(20)

            Spacer(minLength: 0)
            Divider()

            HStack {
                Button("跳过") { onFinish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("开始使用 SnapAI") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(16)
        }
        .frame(width: 480, height: 460)
        .onAppear { perm.refresh() }
    }

    private var isAIConfigurationReady: Bool {
        guard let provider = settings.activeProvider, !provider.apiKey.isEmpty else { return false }
        return !settings.model.isEmpty && provider.enabledModelNames.contains(settings.model)
    }

    @ViewBuilder
    private func stepRow<Trailing: View>(
        number: Int,
        title: String,
        desc: String,
        done: Bool,
        showCheck: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.accentColor.opacity(0.18))
                    .frame(width: 28, height: 28)
                if showCheck && done {
                    Image(systemName: "checkmark").foregroundStyle(.white).font(.system(size: 13, weight: .bold))
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(done ? .white : Color.accentColor)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(desc).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing()
        }
    }
}
