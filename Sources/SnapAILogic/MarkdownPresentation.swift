import Foundation

public enum MarkdownPresentationBlock: Equatable {
    case heading(level: Int, content: AttributedString)
    case paragraph(AttributedString)
    case bullet([AttributedString])
    case ordered([AttributedString])
    case quote(AttributedString)
    case code(String, language: String?)
}

public struct MarkdownPresentation: Equatable {
    public var blocks: [MarkdownPresentationBlock]

    public init(blocks: [MarkdownPresentationBlock] = []) {
        self.blocks = blocks
    }
}

public enum MarkdownPresentationRefreshPolicy {
    public static func shouldPublish(requestGeneration: Int,
                                     currentGeneration: Int,
                                     requestedText: String,
                                     currentText: String) -> Bool {
        requestGeneration == currentGeneration && requestedText == currentText
    }
}

public enum MarkdownPresentationBuilder {
    public static func build(_ text: String) -> MarkdownPresentation {
        MarkdownPresentation(blocks: parse(text).map(presentationBlock))
    }

    private enum RawBlock {
        case heading(level: Int, content: String)
        case paragraph(String)
        case bullet([String])
        case ordered([String])
        case quote(String)
        case code(String, language: String?)
    }

    private static func presentationBlock(_ block: RawBlock) -> MarkdownPresentationBlock {
        switch block {
        case .heading(let level, let content):
            return .heading(level: level, content: inline(content))
        case .paragraph(let content):
            return .paragraph(inline(content))
        case .bullet(let items):
            return .bullet(items.map(inline))
        case .ordered(let items):
            return .ordered(items.map(inline))
        case .quote(let content):
            return .quote(inline(content))
        case .code(let code, let language):
            return .code(code, language: language)
        }
    }

    private static func inline(_ raw: String) -> AttributedString {
        guard raw.utf8.contains(where: { byte in
            switch byte {
            case 0x21, 0x26, 0x2A, 0x3C, 0x3E, 0x5B, 0x5C, 0x5D, 0x5F, 0x60: return true
            default: return false
            }
        }) else { return AttributedString(raw) }
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: raw, options: options)) ?? AttributedString(raw)
    }

    private static func parse(_ text: String) -> [RawBlock] {
        var blocks: [RawBlock] = []
        let normalized = text.utf8.contains(0x0D)
            ? text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            : text
        let lines = normalized.components(separatedBy: "\n")
        var index = 0
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = parseFence(trimmed) {
                flushParagraph()
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if let closing = parseFence(candidate),
                       closing.marker == fence.marker,
                       closing.length >= fence.length,
                       closing.info.isEmpty { break }
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(codeLines.joined(separator: "\n"),
                                    language: fence.info.isEmpty ? nil : fence.info))
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, content: heading.content))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let value = lines[index].trimmingCharacters(in: .whitespaces)
                    guard value.hasPrefix(">") else { break }
                    quoteLines.append(String(value.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            if isBullet(trimmed) {
                flushParagraph()
                var items: [String] = []
                while index < lines.count,
                      isBullet(lines[index].trimmingCharacters(in: .whitespaces)) {
                    let value = lines[index].trimmingCharacters(in: .whitespaces)
                    items.append(String(value.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.bullet(items))
                continue
            }

            if isOrdered(trimmed) {
                flushParagraph()
                var items: [String] = []
                while index < lines.count,
                      isOrdered(lines[index].trimmingCharacters(in: .whitespaces)) {
                    let value = lines[index].trimmingCharacters(in: .whitespaces)
                    if let dot = value.firstIndex(of: ".") {
                        items.append(String(value[value.index(after: dot)...])
                            .trimmingCharacters(in: .whitespaces))
                    }
                    index += 1
                }
                blocks.append(.ordered(items))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            paragraphBuffer.append(trimmed)
            index += 1
        }
        flushParagraph()
        return blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, content: String)? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for character in line {
            if character == "#" {
                level += 1
                if level > 6 { return nil }
            } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isBullet(_ line: String) -> Bool {
        let prefix = line.prefix(2)
        return prefix == "- " || prefix == "* " || prefix == "+ "
    }

    private static func isOrdered(_ line: String) -> Bool {
        guard let first = line.first, first.isASCII, first.isNumber else { return false }
        guard let dot = line.firstIndex(of: ".") else { return false }
        let number = line[..<dot]
        guard number.count <= 9, number.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        let after = line.index(after: dot)
        return after < line.endIndex && line[after] == " "
    }

    private static func parseFence(_ line: String) -> (marker: Character, length: Int, info: String)? {
        guard let marker = line.first, marker == "`" || marker == "~" else { return nil }
        let length = line.prefix { $0 == marker }.count
        guard length >= 3 else { return nil }
        let info = line.dropFirst(length).trimmingCharacters(in: .whitespaces)
        guard marker != "`" || !info.contains("`") else { return nil }
        return (marker, length, info)
    }
}
