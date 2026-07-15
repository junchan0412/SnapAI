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
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭操作提示")
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(feedback.message)
    }

    private var tint: Color {
        SnapAIUI.StatusColor.tint(for: feedback.kind)
    }
}
