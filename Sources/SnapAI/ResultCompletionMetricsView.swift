import SwiftUI
import SnapAILogic

struct ResultInlineMetricsLabel: View {
    @ObservedObject var state: ResultCompletionState

    var body: some View {
        let metrics = state.metrics
        if metrics.characterCount > 0 || metrics.elapsed > 0 {
            let parts: [String] = [
                metrics.elapsed > 0 ? String(format: "%.1fs", metrics.elapsed) : nil,
                metrics.characterCount > 0 ? "\(metrics.characterCount) 字" : nil
            ].compactMap { $0 }
            Text(parts.joined(separator: " · "))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

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
                        .help("网络请求耗时（不含逐字展示时间）")
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
                .help("\(ResultDiagnosticsCommand.briefTitle)")
                .accessibilityLabel(ResultDiagnosticsCommand.briefTitle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func privacyTone(for status: String) -> SnapAISemanticPill.Tone {
        if status.contains("高风险") { return .warning }
        if status.contains("保护") || status.contains("过滤") || status.contains("脱敏") { return .info }
        return .neutral
    }
}
