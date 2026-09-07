import SwiftUI
import AppKit
import SnapAILogic

struct PermissionSettingsSection: View {
    @ObservedObject var permissionState: PermissionState
    @State private var screenCaptureGranted = ScreenCapturePermission.isGranted()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SnapAIUI.looseSpacing) {
                permissionGroup
                screenCaptureGroup
            }
            .padding(SnapAIUI.edgePadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private var permissionGroup: some View {
        VStack(alignment: .leading, spacing: SnapAIUI.standardSpacing) {
            Text("辅助功能")
                .font(SnapAIUI.Typography.sectionLabel)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: SnapAIUI.tightSpacing) {
                permissionStatusRow
                Divider().opacity(0.55)
                permissionActionsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .snapAISurface(padding: SnapAIUI.compactPadding, fillOpacity: SnapAIUI.quietFillOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionStatusRow: some View {
        HStack(spacing: SnapAIUI.standardSpacing) {
            Image(systemName: permissionState.axGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(permissionState.axGranted ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(permissionState.axGranted ? "已授予辅助功能权限" : "未授予辅助功能权限")
                    .font(SnapAIUI.Typography.bodyText.weight(.medium))
                Text("用于读取选中文字和写回结果。直接输入文字不需要此权限。")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var permissionActionsRow: some View {
        HStack(spacing: SnapAIUI.tightSpacing) {
            Button("打开系统设置") {
                NSWorkspace.shared.open(SystemPrivacySettings.accessibilityURL)
            }
            Button("重新检测") {
                refreshPermissions()
            }
            Spacer()
        }
    }

    private var screenCaptureGroup: some View {
        VStack(alignment: .leading, spacing: SnapAIUI.standardSpacing) {
            Text("屏幕录制")
                .font(SnapAIUI.Typography.sectionLabel)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: SnapAIUI.tightSpacing) {
                HStack(spacing: SnapAIUI.standardSpacing) {
                    Image(systemName: screenCaptureGranted ? "checkmark.circle.fill" : "camera")
                        .font(.title3)
                        .foregroundStyle(screenCaptureGranted ? SnapAIUI.StatusColor.success : Color.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(screenCaptureGranted ? "已授予屏幕录制权限" : "需要截图时再授权")
                            .font(SnapAIUI.Typography.bodyText.weight(.medium))
                        Text("仅用于截取屏幕并附加到提问。粘贴图片不需要此权限。")
                            .font(SnapAIUI.Typography.metaText)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Divider().opacity(0.55)
                HStack(spacing: SnapAIUI.tightSpacing) {
                    Button("打开屏幕录制设置") {
                        NSWorkspace.shared.open(SystemPrivacySettings.screenCaptureURL)
                    }
                    Button("重新检测", action: refreshPermissions)
                    Spacer()
                }
            }
            .snapAISurface(padding: SnapAIUI.compactPadding)
        }
    }

    private func refreshPermissions() {
        permissionState.refresh()
        screenCaptureGranted = ScreenCapturePermission.isGranted()
    }
}
