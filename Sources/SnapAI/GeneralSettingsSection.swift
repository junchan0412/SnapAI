import SnapAILogic
import SwiftUI

struct GeneralSettingsSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissionState: PermissionState
    @ObservedObject var ui: AISettingsUI
    let iCloudSyncStatusText: String
    let commit: () -> Void
    let applyCommit: (SettingsCommitPolicy) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SnapAIUI.looseSpacing) {
                WorkModeSettingsSection(settings: settings) {
                    commit()
                }
                appIconSection
                behaviorAndCaptureSection
                PrivacySettingsSection(settings: settings,
                                       ui: ui,
                                       commit: commit,
                                       applyCommit: applyCommit)
                ContextProfileSettingsSection(settings: settings,
                                              ui: ui,
                                              commit: commit,
                                              applyCommit: applyCommit)
                ConfigMigrationSettingsSection(settings: settings,
                                               iCloudSyncStatusText: iCloudSyncStatusText,
                                               commit: commit)
            }
            .padding(SnapAIUI.edgePadding)
        }
        .snapAIScrollEdge()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var appIconSection: some View {
        let previewIsDark = settings.appIconAppearance.resolvesToDark(systemIsDark: colorScheme == .dark)
        return SnapAISectionGroup("应用图标", subtitle: "自由切换多套棱镜主题，并独立设置图标的浅色与深色表现（实时同步 Dock 与侧栏）") {
            Picker("图标外观", selection: $settings.appIconAppearance) {
                ForEach(AppIconAppearance.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 196)
            .accessibilityLabel("图标外观模式")
            .onChange(of: settings.appIconAppearance) { commit() }
        } content: {
            HStack(spacing: 10) {
                ForEach(AppIconStyle.allCases) { style in
                    appIconThemeCard(style: style, isDark: previewIsDark)
                }
            }
            .padding(12)
        }
    }

    private func appIconThemeCard(style: AppIconStyle, isDark: Bool) -> some View {
        let isSelected = settings.appIconStyle == style
        return Button {
            guard settings.appIconStyle != style else { return }
            settings.appIconStyle = style
            commit()
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    SnapAIAppIcon(settings: settings,
                                  size: 56,
                                  styleOverride: style,
                                  isDarkOverride: isDark)
                        .frame(maxWidth: .infinity)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .background(Circle().fill(.background).padding(2))
                    }
                }

                VStack(spacing: 2) {
                    Text(style.title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(style.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? SnapAIUI.Surface.selected : Color.primary.opacity(0.03))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.65) : SnapAIUI.Surface.border,
                        lineWidth: isSelected ? 1.5 : 0.75
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("应用图标：\(style.title)（\(style.subtitle)）")
        .accessibilityValue(isSelected ? "当前已选" : "点击切换")
    }

    private var behaviorAndCaptureSection: some View {
        SnapAISectionGroup("启动、交互与取词") {
            EmptyView()
        } content: {
            settingsToggleRow(
                title: "登录时自动启动",
                description: "开机后在菜单栏静默待命；Dock 图标仅在打开主窗口时显现。",
                icon: "power.circle",
                tint: .green,
                isOn: Binding(
                    get: { permissionState.launchAtLogin },
                    set: { permissionState.setLaunchAtLogin($0) }
                )
            )

            SnapAIFormDivider()

            settingsToggleRow(
                title: "优先辅助功能无感取词",
                description: "优先直接读取选区而不改动剪贴板；不支持的应用自动回退为模拟 ⌘C。",
                icon: "contextualmenu.and.cursorarrow",
                tint: .accentColor,
                isOn: Binding(
                    get: { settings.useAXFirst },
                    set: { settings.useAXFirst = $0; commit() }
                )
            )

            SnapAIFormDivider()

            SnapAISettingRow(
                title: "结果面板失焦行为",
                subtitle: settings.resultPanelDismissMode.description,
                icon: "macwindow.on.rectangle",
                iconTint: .purple
            ) {
                Picker("", selection: $settings.resultPanelDismissMode) {
                    ForEach(ResultPanelDismissMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 224)
                .onChange(of: settings.resultPanelDismissMode) { commit() }
            }

            SnapAIFormDivider()

            SnapAISettingRow(
                title: "打字机展示节奏",
                subtitle: "控制流式回答逐字呈现的视觉节奏（遵循系统「减弱动态效果」）。",
                icon: "character.textbox",
                iconTint: .orange
            ) {
                Picker("", selection: $settings.typewriterSpeed) {
                    ForEach(TypewriterSpeed.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 196)
                .onChange(of: settings.typewriterSpeed) { commit() }
            }
        }
    }

    private func settingsToggleRow(title: String,
                                   description: String,
                                   icon: String,
                                   tint: Color,
                                   isOn: Binding<Bool>) -> some View {
        SnapAISettingRow(title: title, subtitle: description, icon: icon, iconTint: tint) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
    }
}
