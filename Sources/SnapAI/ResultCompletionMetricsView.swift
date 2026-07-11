import SwiftUI
import SnapAILogic

struct ResultCompletionMetricsRow: View {
    @ObservedObject var state: ResultCompletionState
    let privacyStatus: String?
    let canCopyBriefDiagnostics: Bool
    var onCopyBriefDiagnostics: () -> Void

    var body: some View {
        let metrics = state.metrics
        if metrics.characterCount > 0 || metrics.elapsed > 0 {
            HStack(spacing: 10) {
                if metrics.elapsed > 0 {
                    Label(String(format: "%.1fs", metrics.elapsed), systemImage: "clock")
                }
                if metrics.characterCount > 0 {
                    Label("\(metrics.characterCount) 字", systemImage: "textformat")
                }
                Spacer(minLength: 0)
                if let privacyStatus {
                    Label(privacyStatus, systemImage: "hand.raised")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(privacyStatus)
                        .layoutPriority(1)
                }
                Button(action: onCopyBriefDiagnostics) {
                    Image(systemName: ResultDiagnosticsCommand.systemImage)
                }
                .buttonStyle(.plain)
                .disabled(!canCopyBriefDiagnostics)
                .help(ResultDiagnosticsCommand.briefTitle)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
