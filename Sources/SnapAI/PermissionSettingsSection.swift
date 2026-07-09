import SwiftUI
import AppKit
import SnapAILogic

struct PermissionSettingsSection: View {
    @ObservedObject var permissionState: PermissionState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                permissionGroup
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var permissionGroup: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("辅助功能")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 8) {
                permissionStatusRow
                Divider().opacity(0.55)
                permissionActionsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .snapAISurface(padding: 9, fillOpacity: SnapAIUI.quietFillOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionStatusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: permissionState.axGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(permissionState.axGranted ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(permissionState.axGranted ? "已授予辅助功能权限" : "未授予辅助功能权限")
                    .font(.callout.weight(.medium))
                Text("SnapAI 需要该权限来读取选中文字并模拟复制按键。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var permissionActionsRow: some View {
        HStack(spacing: 8) {
            Button("打开系统设置") {
                NSWorkspace.shared.open(SystemPrivacySettings.accessibilityURL)
            }
            Button("重新检测") {
                permissionState.refresh(prompt: true)
            }
            Spacer()
        }
    }
}
