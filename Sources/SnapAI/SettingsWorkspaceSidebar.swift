import SwiftUI
import SnapAILogic

struct SettingsWorkspaceSidebar: View {
    @Binding var selection: SettingsSection
    @ObservedObject var settings: AppSettings
    let commit: () -> Void
    let providerName: String?
    let modelName: String
    let shortcut: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SnapAIAppIcon(settings: settings, size: 34)
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("SnapAI")
                        .font(.system(size: 15.5, weight: .semibold))
                    Text("跨应用 AI 效率助手")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 14)

            List(selection: Binding<SettingsSection?>(
                get: { selection.sidebarSection },
                set: { if let section = $0 { selection = section } }
            )) {
                Section("核心配置") {
                    sidebarRow(.model)
                    sidebarRow(.actions)
                }
                Section("记录与系统") {
                    sidebarRow(.history)
                    sidebarRow(.general)
                    sidebarRow(.permission)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .snapAIChrome()

            VStack(alignment: .leading, spacing: 10) {
                SnapAIFormDivider(inset: 0)

                HStack(spacing: 8) {
                    Circle()
                        .fill(modelName.isEmpty ? Color.orange : SnapAIUI.StatusColor.success)
                        .frame(width: 6.5, height: 6.5)
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(modelName.isEmpty ? "尚未配置模型" : modelName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(modelName.isEmpty ? "在「模型与服务」中添加" : (providerName ?? "就绪"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    Text("快捷提问")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    SnapAIKeycap(text: shortcut)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .snapAISidebarGlass()
        .navigationSplitViewColumnWidth(min: 196, ideal: 212, max: 236)
    }

    private func sidebarRow(_ section: SettingsSection) -> some View {
        SettingsSidebarRow(section: section, isSelected: selection.sidebarSection == section)
            .tag(section)
    }
}
