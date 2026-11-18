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
        LazyVStack(alignment: .leading, spacing: 10) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, index == 0 ? 0 : (level <= 2 ? 8 : 5))
                .padding(.bottom, 1)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let content):
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .list(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        listMarker(items[i].marker)
                            .foregroundStyle(.secondary)
                        Text(items[i].content)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CGFloat(items[i].depth) * 18)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.leading, 4)

        case .quote(let content):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: 3)
                Text(content)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .padding(.leading, 2)

        case .code(let code, let language):
            CodeBlockView(code: code,
                          highlightedCode: model.result.codeText[index],
                          language: language,
                          onCopy: onCopyCode)

        case .table(let table):
            MarkdownTableView(table: table)
        }
    }

    @ViewBuilder
    private func listMarker(_ marker: MarkdownListItem.Marker) -> some View {
        switch marker {
        case .bullet:
            Text("•")
                .font(.system(size: 13, weight: .bold))
                .accessibilityLabel("列表项")
        case .ordered(let number):
            Text("\(number).")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
        case .task(let completed):
            Image(systemName: completed ? "checkmark.square.fill" : "square")
                .font(.system(size: 12.5))
                .foregroundStyle(completed ? Color.accentColor : .secondary)
                .accessibilityLabel(completed ? "已完成" : "未完成")
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 18, weight: .semibold)
        case 2: return .system(size: 16, weight: .semibold)
        case 3: return .system(size: 14.5, weight: .semibold)
        default: return .system(size: 13.5, weight: .semibold)
        }
    }
}

private struct CodeBlockView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let code: String
    let highlightedCode: AttributedString?
    let language: String?
    let onCopy: (String) -> Void
    @StateObject private var copyFeedback = SnapAITransientState<Bool>()
    private var copied: Bool { copyFeedback.value == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language?.isEmpty == false ? language! : "code").lowercased())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onCopy(code)
                    copyFeedback.show(true, autoDismiss: 1.4)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "已复制" : "复制")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? SnapAIUI.StatusColor.success : .secondary)
                .help("复制代码块")
                .accessibilityLabel(copied ? "已复制" : "复制代码块")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.035))

            SnapAIFormDivider(inset: 0)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(highlightedCode ?? AttributedString(code))
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineSpacing(2.5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel("代码，支持横向滚动")
        }
        .background(
            colorScheme == .dark ? Color.black.opacity(0.28) : Color(nsColor: .textBackgroundColor).opacity(0.85),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SnapAIUI.Surface.border, lineWidth: 0.75)
        }
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
                        cell(table.headers[column], column: column, isHeader: true)
                            .background(Color.primary.opacity(0.05))
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                ForEach(table.rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(table.headers.indices, id: \.self) { column in
                            cell(table.rows[row][column], column: column, isHeader: false)
                                .accessibilityLabel("\(String(table.headers[column].characters)): \(String(table.rows[row][column].characters))")
                        }
                    }
                }
            }
            .textSelection(.enabled)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(SnapAIUI.Surface.border, lineWidth: 0.75)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("表格，\(table.headers.count) 列，\(table.rows.count) 行，支持横向滚动")
    }

    private func cell(_ content: AttributedString, column: Int, isHeader: Bool) -> some View {
        Text(content)
            .font(.system(size: 12.5, weight: isHeader ? .semibold : .regular))
            .frame(minWidth: 96, idealWidth: 170, maxWidth: 280, alignment: alignment(column))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(column))
            .overlay(alignment: .bottom) {
                Rectangle().fill(SnapAIUI.Surface.divider).frame(height: 0.75)
            }
    }

    private func alignment(_ column: Int) -> Alignment {
        switch table.alignments[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
