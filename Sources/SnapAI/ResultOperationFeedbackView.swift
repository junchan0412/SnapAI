import SwiftUI
import SnapAILogic

struct ResultOperationFeedbackHost: View {
    @ObservedObject var coordinator: ResultOperationCoordinator

    var body: some View {
        Group {
            if let feedback = coordinator.feedback {
                ResultOperationFeedbackBanner(feedback: feedback) {
                    coordinator.dismissFeedback(id: feedback.id)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .task(id: feedback.id) {
                    try? await Task.sleep(for: .seconds(feedback.dismissDelaySeconds))
                    guard !Task.isCancelled else { return }
                    coordinator.dismissFeedback(id: feedback.id)
                }
            }
        }
        .animation(.easeInOut(duration: 0.16), value: coordinator.feedback?.id)
    }
}

struct ResultOperationFeedbackBanner: View {
    let feedback: ResultOperationFeedback
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Label(feedback.message, systemImage: feedback.systemImage)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭操作提示")
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(tint.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(feedback.message)
    }

    private var tint: Color {
        switch feedback.kind {
        case .success: return .green
        case .warning: return .orange
        }
    }
}
