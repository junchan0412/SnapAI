import SnapAILogic
import SwiftUI

struct ResultSourceSection: View {
    @Binding var text: String
    @Binding var isExpanded: Bool
    let isStreaming: Bool
    var hasImage = false
    var onResend: () -> Void

    private var preview: String {
        let prefix = text.prefix(140)
        return prefix.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: hasImage ? "photo.badge.plus" : "quote.opening")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("原文")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if !isExpanded {
                        Text(preview.isEmpty ? (hasImage ? "含图片附件，点击查看或补充说明" : "点击展开输入原文") : preview)
                            .font(SnapAIUI.Typography.metaText)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起原文" : "展开原文")

            if isExpanded {
                SnapAIFormDivider(inset: 11)
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $text)
                        .font(SnapAIUI.Typography.bodyText)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 72, maxHeight: 150)
                        .snapAIGlassField(radius: 6)
                        .disabled(isStreaming)
                        .accessibilityLabel("编辑原文")

                    HStack {
                        Text(isStreaming ? "生成完成后可修改并重发" : (hasImage ? "重发时将保留原图片附件" : "修改原文后重新执行当前动作"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button(action: onResend) {
                            Label("重新发送", systemImage: "arrow.up")
                        }
                        .buttonStyle(SnapAIPrimaryButtonStyle(compact: true))
                        .disabled(isStreaming || (!hasImage && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    }
                }
                .padding(10)
            }
        }
        .snapAIGlassCard(radius: 9)
    }
}
