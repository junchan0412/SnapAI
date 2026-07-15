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
                    Label("耗时 \(String(format: "%.1fs", metrics.elapsed))", systemImage: "clock")
                }
                if metrics.characterCount > 0 {
                    Label("\(metrics.characterCount) 字", systemImage: "textformat")
                }
                Spacer(minLength: 0)
                if let privacyStatus {
                    SnapAISemanticPill(title: privacyStatus,
                                       systemImage: "hand.raised",
                                       tone: privacyTone(for: privacyStatus))
                        .help(privacyStatus)
                        .layoutPriority(1)
                }
                Button(action: onCopyBriefDiagnostics) {
                    Image(systemName: ResultDiagnosticsCommand.systemImage)
                }
                .buttonStyle(.plain)
                .disabled(!canCopyBriefDiagnostics)
                .help("\(ResultDiagnosticsCommand.briefTitle)(复制精简诊断)")
                .accessibilityLabel(ResultDiagnosticsCommand.briefTitle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// 隐私状态含「高风险」时用警告色,「保护/已过滤」时用信息色,常态用中性色。
    private func privacyTone(for status: String) -> SnapAISemanticPill.Tone {
        if status.contains("高风险") { return .warning }
        if status.contains("保护") || status.contains("过滤") || status.contains("脱敏") { return .info }
        return .neutral
    }
}
