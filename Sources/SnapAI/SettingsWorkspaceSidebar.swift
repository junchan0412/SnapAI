import SwiftUI
import SnapAILogic

struct SettingsWorkspaceSidebar: View {
    @Binding var selection: SettingsSection
    let providerName: String?
    let modelName: String
    let shortcut: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(SnapAIUI.Surface.selected,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("SnapAI")
                        .font(.system(size: 18, weight: .semibold))
                    Text("你的随身 AI 工作台")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)

            List(selection: Binding<SettingsSection?>(
                get: { selection },
                set: { if let section = $0 { selection = section } }
            )) {
                Section("工作空间") {
                    sidebarRow(.ai)
                    sidebarRow(.actions)
                    sidebarRow(.history)
                }
                Section("偏好设置") {
                    sidebarRow(.general)
                    sidebarRow(.permission)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 12) {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Label(modelName.isEmpty ? "等待配置模型" : "当前模型",
                          systemImage: modelName.isEmpty ? "circle.dashed" : "circle.inset.filled")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(modelName.isEmpty ? "添加一个模型，即可开始" : modelName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let providerName, !modelName.isEmpty {
                        Text(providerName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    Text("快捷提问")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    SnapAIKeycap(text: shortcut)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
    }

    private func sidebarRow(_ section: SettingsSection) -> some View {
        SettingsSidebarRow(section: section, isSelected: selection == section)
            .tag(section)
    }
}
