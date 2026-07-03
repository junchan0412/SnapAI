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
    @Published var showRoutingDiagnostics: Bool = false
    @Published var hotKeyConflictDestination: HotKeyConflictDetector.Conflict.Target?
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

enum SettingsCommitPolicy {
    case fullReload
    case saveOnly
    case deferredSave
}

struct SettingsSidebarRow: View {
    let section: SettingsSection

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .lineLimit(1)
                Text(section.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel(section.title)
    }
}
