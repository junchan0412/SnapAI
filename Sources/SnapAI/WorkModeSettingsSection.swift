import SnapAILogic
import SwiftUI

struct WorkModeSettingsSection: View {
    @ObservedObject var settings: AppSettings
    var onCommit: () -> Void

    var body: some View {
        SnapAISectionGroup("工作模式预设", subtitle: settings.workModeStatusDetail) {
            SnapAIStatusPill(title: settings.workModeStatusTitle,
                             systemImage: settings.matchingWorkModePreset?.systemImage ?? "slider.horizontal.2.square",
                             tint: .accentColor,
                             filled: true)
        } content: {
            HStack(spacing: 8) {
                ForEach(WorkModePreset.allCases) { mode in
                    workModeButton(mode)
                }
            }
            .padding(12)
        }
    }

    private func workModeButton(_ mode: WorkModePreset) -> some View {
        let isCurrent = settings.matchingWorkModePreset == mode
        return Button {
            settings.applyWorkMode(mode)
            onCommit()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                    Text(mode.shortTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(mode.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .background(
                isCurrent ? Color.accentColor.opacity(0.10) : SnapAIUI.Surface.quiet,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isCurrent ? Color.accentColor.opacity(0.38) : SnapAIUI.Surface.border,
                                  lineWidth: isCurrent ? 1.2 : 0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("切换为「\(mode.shortTitle)」模式")
    }
}
