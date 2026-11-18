import SwiftUI
import AppKit
import SnapAILogic

/// 主窗口「权限与诊断」页：整合原「权限」页与「权限健康中心」独立窗口，一站查看授权、热键与诊断状态。
struct PermissionSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissionState: PermissionState
    @ObservedObject var navigation: SettingsNavigationModel
    var hotKeyFailures: () -> [String] = { [] }
    var textCaptureStatus: () -> String = { "就绪" }
    var writeBackStatus: () -> String = { "就绪" }
    var recentAIRequestStatus: () -> String = { "none" }

    @StateObject private var healthHolder: PermissionHealthModelHolder

    init(settings: AppSettings,
         permissionState: PermissionState,
         navigation: SettingsNavigationModel,
         hotKeyFailures: @escaping () -> [String] = { [] },
         textCaptureStatus: @escaping () -> String = { "就绪" },
         writeBackStatus: @escaping () -> String = { "就绪" },
         recentAIRequestStatus: @escaping () -> String = { "none" }) {
        self.settings = settings
        self.permissionState = permissionState
        self.navigation = navigation
        self.hotKeyFailures = hotKeyFailures
        self.textCaptureStatus = textCaptureStatus
        self.writeBackStatus = writeBackStatus
        self.recentAIRequestStatus = recentAIRequestStatus
        _healthHolder = StateObject(wrappedValue: PermissionHealthModelHolder(
            settings: settings,
            hotKeyFailures: hotKeyFailures,
            textCaptureStatus: textCaptureStatus,
            writeBackStatus: writeBackStatus,
            recentAIRequestStatus: recentAIRequestStatus
        ))
    }

    var body: some View {
        PermissionHealthView(
            model: healthHolder.model,
            embeddedInWorkspace: true,
            onNavigateToModels: {
                navigation.select(.provider)
            }
        )
    }
}

@MainActor
private final class PermissionHealthModelHolder: ObservableObject {
    let model: PermissionHealthModel

    init(settings: AppSettings,
         hotKeyFailures: @escaping () -> [String],
         textCaptureStatus: @escaping () -> String,
         writeBackStatus: @escaping () -> String,
         recentAIRequestStatus: @escaping () -> String) {
        self.model = PermissionHealthModel(
            settings: settings,
            hotKeyFailures: hotKeyFailures,
            textCaptureStatus: textCaptureStatus,
            writeBackStatus: writeBackStatus,
            recentAIRequestStatus: recentAIRequestStatus
        )
    }
}
