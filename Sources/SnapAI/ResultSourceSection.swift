import SnapAILogic
import SwiftUI

struct ResultSourceSection: View {
    @Binding var text: String
    @Binding var isExpanded: Bool
    let isStreaming: Bool
    var onResend: () -> Void

    private var preview: String {
        let prefix = text.prefix(140)
        return prefix.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $text)
                    .font(SnapAIUI.Typography.bodyText)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 76, maxHeight: 160)
                    .background(SnapAIUI.Surface.field,
                                in: RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous)
                            .stroke(SnapAIUI.Surface.divider, lineWidth: 1)
                    }
                    .disabled(isStreaming)
                    .accessibilityLabel("编辑原文")
                HStack {
                    Text(isStreaming ? "生成完成后可修改原文" : "修改原文后，使用当前动作重新处理。")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button(action: onResend) {
                        Label("重新发送", systemImage: "arrow.up")
                    }
                    .controlSize(.small)
                    .disabled(isStreaming || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 8) {
                Text("原文")
                    .font(SnapAIUI.Typography.sectionLabel)
                if !isExpanded {
                    Text(preview.isEmpty ? "展开以添加文字" : preview)
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(12)
        .background(SnapAIUI.Surface.quiet,
                    in: RoundedRectangle(cornerRadius: SnapAIUI.cardRadius, style: .continuous))
    }
}
