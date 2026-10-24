import SwiftUI
import SnapAILogic

/// 完成态 Markdown 渲染器；block 与行内 attributed content 在后台预构建。
struct MarkdownView: View, Equatable {
    let text: String
    var onPresentationReady: () -> Void = {}
    var onCopyCode: (String) -> Void = { _ in }
    var bottomAnchorID: String?
    @StateObject private var model = MarkdownPresentationModel()
    @State private var notifiedBottomAnchorText: String?
    @State private var notifiedPresentationText: String?

    static func == (lhs: MarkdownView, rhs: MarkdownView) -> Bool {
        lhs.text == rhs.text && lhs.bottomAnchorID == rhs.bottomAnchorID
    }

    var body: some View {
        Group {
            if let presentation = model.presentation(for: text) {
                content(presentation)
                    .onAppear {
                        guard notifiedPresentationText != text else { return }
                        notifiedPresentationText = text
                        onPresentationReady()
                    }
            } else {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: text) {
            model.refresh(text: text)
        }
    }

    private func content(_ presentation: MarkdownPresentation) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(presentation.blocks.indices, id: \.self) { index in
                view(for: presentation.blocks[index], index: index)
            }
            if let bottomAnchorID {
                Color.clear.frame(height: 1).id(bottomAnchorID)
                    .accessibilityHidden(true)
                    .onAppear {
                        guard notifiedBottomAnchorText != text else { return }
                        notifiedBottomAnchorText = text
                        onPresentationReady()
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownPresentationBlock, index: Int) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(content)
                .font(headingFont(level))
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level <= 2 ? 8 : 6)
                .padding(.bottom, 3)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let content):
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .list(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 6) {
                        listMarker(items[index].marker)
                            .foregroundStyle(.secondary)
                        Text(items[index].content).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CGFloat(items[index].depth) * 20)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.leading, 6)

        case .quote(let content):
            HStack(spacing: 8) {
                Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                Text(content).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
            .snapAIGlassCard(radius: SnapAIUI.controlRadius)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)

        case .code(let code, let language):
            CodeBlockView(code: code, highlightedCode: model.result.codeText[index],
                          language: language, onCopy: onCopyCode)

        case .table(let table):
            MarkdownTableView(table: table)
        }
    }

    @ViewBuilder
    private func listMarker(_ marker: MarkdownListItem.Marker) -> some View {
        switch marker {
        case .bullet:
            Text("•").accessibilityLabel("列表项")
        case .ordered(let number):
            Text("\(number).").monospacedDigit()
        case .task(let completed):
            Image(systemName: completed ? "checkmark.square" : "square")
                .accessibilityLabel(completed ? "已完成" : "未完成")
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

/// 代码块:等宽字体 + 背景 + 复制按钮(复制后内联显示「已复制」)
private struct CodeBlockView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let code: String
    let highlightedCode: AttributedString?
    let language: String?
    let onCopy: (String) -> Void
    @StateObject private var copyFeedback = SnapAITransientState<Bool>()
    private var copied: Bool { copyFeedback.value == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onCopy(code)
                    copyFeedback.show(true, autoDismiss: 1.4)
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? SnapAIUI.StatusColor.success : .secondary)
                .help("复制代码块")
                .accessibilityLabel(copied ? "已复制" : "复制代码块")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            ScrollView(.horizontal) {
                Text(highlightedCode ?? AttributedString(code))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel("代码，支持横向滚动")
        }
        .snapAIGlassCard(radius: SnapAIUI.controlRadius)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: copied)
        .onDisappear { copyFeedback.clear() }
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(table.headers.indices, id: \.self) { column in
                        cell(table.headers[column], column: column)
                            .fontWeight(.semibold)
                            .background(Color.primary.opacity(0.06))
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                ForEach(table.rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(table.headers.indices, id: \.self) { column in
                            cell(table.rows[row][column], column: column)
                                .background(Color.primary.opacity(row.isMultiple(of: 2) ? 0.02 : 0.04))
                                .accessibilityLabel("\(String(table.headers[column].characters)): \(String(table.rows[row][column].characters))")
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .padding(1)
        }
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("表格，\(table.headers.count) 列，\(table.rows.count) 行，支持横向滚动")
    }

    private func cell(_ content: AttributedString, column: Int) -> some View {
        Text(content)
            .frame(minWidth: 100, idealWidth: 180, maxWidth: 280, alignment: alignment(column))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(column))
            .overlay(alignment: .bottom) { Divider() }
    }

    private func alignment(_ column: Int) -> Alignment {
        switch table.alignments[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
