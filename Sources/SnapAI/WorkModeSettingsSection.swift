import SwiftUI

struct WorkModeSettingsSection: View {
    @ObservedObject var settings: AppSettings
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("工作模式")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: settings.matchingWorkModePreset?.systemImage ?? "slider.horizontal.2.square")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.workModeStatusTitle)
                            .font(.callout.weight(.medium))
                        Text(settings.workModeStatusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                }

                Divider()
                    .opacity(0.55)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 8)], spacing: 8) {
                    ForEach(WorkModePreset.allCases) { mode in
                        workModeButton(mode)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .snapAISurface(padding: 9, fillOpacity: SnapAIUI.quietFillOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workModeButton(_ mode: WorkModePreset) -> some View {
        let isCurrent = settings.matchingWorkModePreset == mode
        return Button {
            settings.applyWorkMode(mode)
            onCommit()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : mode.systemImage)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.shortTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(mode.summary)
                        .font(.caption2)
                        .foregroundStyle(isCurrent ? Color.accentColor.opacity(0.8) : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(SnapAIUI.selectedFillOpacity))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous)
                    .stroke(isCurrent ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08),
                            lineWidth: isCurrent ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("切换到「\(mode.shortTitle)」工作模式")
    }
}
