import SwiftUI
import SnapAILogic

/// 完成态 Markdown 渲染器；block 与行内 attributed content 在后台预构建。
struct MarkdownView: View, Equatable {
    let text: String
    var onPresentationReady: () -> Void = {}
    @StateObject private var model = MarkdownPresentationModel()

    static func == (lhs: MarkdownView, rhs: MarkdownView) -> Bool {
        lhs.text == rhs.text
    }

    var body: some View {
        Group {
            if let presentation = model.presentation(for: text) {
                content(presentation)
            } else {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: text) {
            model.refresh(text: text)
        }
        .onChange(of: model.result) {
            guard model.presentation(for: text) != nil else { return }
            onPresentationReady()
        }
    }

    private func content(_ presentation: MarkdownPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(presentation.blocks.indices, id: \.self) { index in
                view(for: presentation.blocks[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownPresentationBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(content)
                .font(headingFont(level))
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let content):
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        Text(items[index]).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .ordered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                        Text(items[index]).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .quote(let content):
            HStack(spacing: 8) {
                Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                Text(content).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .code(let code, let language):
            CodeBlockView(code: code, language: language)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }
}

/// 代码块:等宽字体 + 背景 + 复制按钮
private struct CodeBlockView: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.isEmpty == false ? language! : "code")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            Text(code)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
