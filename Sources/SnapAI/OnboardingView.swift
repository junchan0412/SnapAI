import SwiftUI
import SnapAILogic

/// 首次启动引导页:介绍 → 权限 → 配置 → 完成
struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    var onFinish: () -> Void
    var openSettings: () -> Void
    /// 点击「试试快捷提问」时触发,直接体验快捷提问面板。
    var onTryQuickInput: (() -> Void)? = nil

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
                    HStack(spacing: 8) {
                        Button("打开设置") { openSettings() }
                        if isAIConfigurationReady {
                            SnapAISemanticPill(title: "已就绪", systemImage: "checkmark.circle.fill", tone: .success)
                        } else {
                            Button {
                                // 设置是 @ObservedObject,改动会自动反映;这里显式触发一次对象刷新提示。
                                settings.objectWillChange.send()
                            } label: {
                                Label("重新检测", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("在设置中保存后点此重新检测配置状态")
                        }
                    }
                }

                stepRow(
                    number: 3,
                    title: "开始使用",
                    desc: "选中文字后用以下快捷键触发,或直接试试快捷提问面板。",
                    done: false,
                    showCheck: false
                ) {
                    VStack(alignment: .trailing, spacing: 6) {
                        shortcutKeycaps
                        if let onTryQuickInput {
                            Button {
                                onTryQuickInput()
                            } label: {
                                Label("试试快捷提问", systemImage: "sparkles")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(!isAIConfigurationReady)
                            .help(isAIConfigurationReady ? "打开快捷提问面板体验一次" : "请先完成上一步的 AI 配置")
                        }
                    }
                }
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
        .frame(minWidth: 480, minHeight: 460)
        .onAppear { perm.refresh() }
    }

    /// 快捷键键帽视觉:把 ⌥A / ⌥T / 快捷提问键渲染成可识别的键帽,提升可发现性。
    private var shortcutKeycaps: some View {
        HStack(spacing: 12) {
            keycapGroup(label: "提问", keys: "⌥A")
            keycapGroup(label: "翻译", keys: "⌥T")
            keycapGroup(label: "快捷提问", keys: settings.quickPanelHotKey.displayString)
        }
    }

    private func keycapGroup(label: String, keys: String) -> some View {
        VStack(spacing: 3) {
            keycap(keys)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
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
                    .fill(done ? SnapAIUI.StatusColor.success : Color.accentColor.opacity(0.18))
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
