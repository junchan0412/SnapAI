import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SnapAILogic

/// 追踪设置界面里的运行时状态(辅助功能权限、开机自启)。
final class PermissionState: ObservableObject {
    @Published var axGranted: Bool = TextCapture.hasAccessibilityPermission()
    @Published var launchAtLogin: Bool = LoginItem.isEnabled

    func refresh(prompt: Bool = false) {
        axGranted = TextCapture.hasAccessibilityPermission(prompt: prompt)
        launchAtLogin = LoginItem.isEnabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        LoginItem.setEnabled(on)
        launchAtLogin = LoginItem.isEnabled
    }
}

/// 负责为某个供应商拉取可用模型列表。
@MainActor
final class ModelLoader: ObservableObject {
    @Published var loadingProviderID: String?
    @Published var errors: [String: String] = [:]

    func isLoading(_ providerID: String) -> Bool { loadingProviderID == providerID }

    func load(providerID: String, settings: AppSettings, onChange: @escaping () -> Void) {
        guard loadingProviderID == nil else { return }
        guard let idx = settings.providers.firstIndex(where: { $0.id == providerID }) else { return }
        loadingProviderID = providerID
        errors[providerID] = nil

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

/// 设置界面的本地 UI 状态。
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
    @Published var showRedactionRules: Bool = false
    @Published var showContextProfiles: Bool = false
    @Published var hotKeyConflictDestination: HotKeyConflictDetector.Conflict.Target?
    var deferredSaveTask: Task<Void, Never>?
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var selectedSection: SettingsSection = .model
    @Published var scrollToProvidersToken: Int = 0

    func select(_ section: SettingsSection) {
        if section == .provider {
            selectedSection = .model
            scrollToProvidersToken &+= 1
        } else {
            selectedSection = section
        }
    }
}

/// 供应商连接测试状态
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
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .font(.system(size: 13.5, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 20)
            Text(section.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityLabel(section.title)
        .accessibilityHint(section.subtitle)
    }
}
