import SwiftUI

/// 轻量 Markdown 渲染器(block 级解析 + 行内用 AttributedString)。
/// 不依赖第三方库;纯函数式构建视图,避开本机 CLT 缺失的 @State 宏。
struct MarkdownView: View {
    let text: String

    var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            inlineText(content)
                .font(headingFont(level))
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let content):
            inlineText(content)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        inlineText(item).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .ordered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(idx + 1).").foregroundStyle(.secondary).monospacedDigit()
                        inlineText(item).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .quote(let content):
            HStack(spacing: 8) {
                Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                inlineText(content).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .code(let code, let lang):
            CodeBlockView(code: code, language: lang)
        }
    }

    /// 行内格式:用系统的 AttributedString markdown 解析(加粗/斜体/行内代码/链接)
    private func inlineText(_ raw: String) -> Text {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let attr = try? AttributedString(markdown: raw, options: options) {
            return Text(attr)
        }
        return Text(raw)
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

// MARK: - 解析

enum MarkdownBlock {
    case heading(level: Int, content: String)
    case paragraph(String)
    case bullet([String])
    case ordered([String])
    case quote(String)
    case code(String, lang: String?)
}

enum MarkdownParser {
    /// 把整段文本切成 block。逐行扫描,合并连续的同类行。
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")

        var i = 0
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            if !paragraphBuffer.isEmpty {
                let joined = paragraphBuffer.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty { blocks.append(.paragraph(joined)) }
                paragraphBuffer.removeAll()
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 代码块 ```
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1 // 跳过结尾 ```
                blocks.append(.code(codeLines.joined(separator: "\n"), lang: lang.isEmpty ? nil : lang))
                continue
            }

            // 标题 #
            if let h = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: h.0, content: h.1))
                i += 1
                continue
            }

            // 引用 >
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    quoteLines.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            // 无序列表 - * +
            if isBullet(trimmed) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count && isBullet(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    items.append(String(t.dropFirst(1)).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.bullet(items))
                continue
            }

            // 有序列表 1. 2.
            if isOrdered(trimmed) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count && isOrdered(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let dotRange = t.range(of: ".") {
                        items.append(String(t[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces))
                    }
                    i += 1
                }
                blocks.append(.ordered(items))
                continue
            }

            // 空行 -> 段落分隔
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // 普通段落行
            paragraphBuffer.append(trimmed)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    private static func parseHeading(_ line: String) -> (Int, String)? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for ch in line { if ch == "#" { level += 1 } else { break } }
        guard level >= 1 && level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isBullet(_ line: String) -> Bool {
        guard line.count >= 2 else { return false }
        let prefix = line.prefix(2)
        return prefix == "- " || prefix == "* " || prefix == "+ "
    }

    private static func isOrdered(_ line: String) -> Bool {
        // 形如 "12. xxx"
        guard let dotIdx = line.firstIndex(of: ".") else { return false }
        let numPart = line[line.startIndex..<dotIdx]
        guard !numPart.isEmpty, numPart.allSatisfy({ $0.isNumber }) else { return false }
        let after = line.index(after: dotIdx)
        return after < line.endIndex && line[after] == " "
    }
}
