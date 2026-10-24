import Foundation

public enum MarkdownPresentationBlock: Equatable {
    case heading(level: Int, content: AttributedString)
    case paragraph(AttributedString)
    case list([MarkdownListItem])
    case quote(AttributedString)
    case code(String, language: String?)
    case table(MarkdownTable)
}

public struct MarkdownListItem: Equatable {
    public enum Marker: Equatable {
        case bullet
        case ordered(Int)
        case task(completed: Bool)
    }

    public var marker: Marker
    public var depth: Int
    public var content: AttributedString
}

public struct MarkdownTable: Equatable {
    public enum Alignment: Equatable { case leading, center, trailing }
    public var headers: [AttributedString]
    public var alignments: [Alignment]
    public var rows: [[AttributedString]]
}

public struct MarkdownPresentation: Equatable {
    public var blocks: [MarkdownPresentationBlock]
    public var codeHighlights: [Int: [MarkdownCodeToken]]

    public init(blocks: [MarkdownPresentationBlock] = [],
                codeHighlights: [Int: [MarkdownCodeToken]] = [:]) {
        self.blocks = blocks
        self.codeHighlights = codeHighlights
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

public struct MarkdownReadingPosition: Equatable {
    public let fraction: Double

    public init?(viewportTop: Double, contentTop: Double, contentHeight: Double) {
        guard contentHeight > 0, viewportTop >= contentTop,
              viewportTop <= contentTop + contentHeight else { return nil }
        fraction = (viewportTop - contentTop) / contentHeight
    }

    public func restoredTop(contentTop: Double, contentHeight: Double,
                            maximumScrollTop: Double) -> Double {
        min(maximumScrollTop, max(0, contentTop + fraction * contentHeight))
    }
}

public enum MarkdownPresentationBuilder {
    public static func build(_ text: String) -> MarkdownPresentation {
        let blocks = parse(text).map(presentationBlock)
        var highlights: [Int: [MarkdownCodeToken]] = [:]
        for (index, block) in blocks.enumerated() {
            if case .code(let code, let language) = block {
                highlights[index] = MarkdownCodeHighlighter.tokens(code, language: language)
            }
        }
        return MarkdownPresentation(blocks: blocks, codeHighlights: highlights)
    }

    private enum RawBlock {
        case heading(level: Int, content: String)
        case paragraph(String)
        case list([RawListItem])
        case quote(String)
        case code(String, language: String?)
        case table(headers: [String], alignments: [MarkdownTable.Alignment], rows: [[String]])
    }

    private struct RawListItem {
        var marker: MarkdownListItem.Marker
        var depth: Int
        var content: String
    }

    private static func presentationBlock(_ block: RawBlock) -> MarkdownPresentationBlock {
        switch block {
        case .heading(let level, let content):
            return .heading(level: level, content: inline(content))
        case .paragraph(let content):
            return .paragraph(inline(content))
        case .list(let items):
            return .list(items.map { MarkdownListItem(marker: $0.marker, depth: $0.depth,
                                                     content: inline($0.content)) })
        case .quote(let content):
            return .quote(inline(content))
        case .code(let code, let language):
            return .code(code, language: language)
        case .table(let headers, let alignments, let rows):
            return .table(MarkdownTable(headers: headers.map(inline), alignments: alignments,
                                        rows: rows.map { $0.map(inline) }))
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

            if index + 1 < lines.count,
               let headers = tableCells(trimmed),
               let alignments = tableAlignments(lines[index + 1]),
               headers.count == alignments.count {
                flushParagraph()
                index += 2
                var rows: [[String]] = []
                while index < lines.count, let cells = tableCells(lines[index]) {
                    rows.append(Array((cells + Array(repeating: "", count: headers.count))
                        .prefix(headers.count)))
                    index += 1
                }
                blocks.append(.table(headers: headers, alignments: alignments, rows: rows))
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

            if listMarker(line) != nil {
                flushParagraph()
                var items: [RawListItem] = []
                var indents: [Int] = []
                while index < lines.count {
                    if let item = listMarker(lines[index]) {
                        while let last = indents.last, last > item.indent { indents.removeLast() }
                        if indents.last != item.indent { indents.append(item.indent) }
                        items.append(RawListItem(marker: item.marker, depth: indents.count - 1,
                                                 content: item.content))
                    } else if !items.isEmpty,
                              !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                              indentation(lines[index]) > (indents.last ?? 0) {
                        items[items.count - 1].content += "\n" + lines[index]
                            .trimmingCharacters(in: .whitespaces)
                    } else {
                        break
                    }
                    index += 1
                }
                blocks.append(.list(items))
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

    private static func indentation(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    private static func listMarker(_ line: String)
        -> (indent: Int, marker: MarkdownListItem.Marker, content: String)? {
        let value = line.trimmingCharacters(in: .whitespaces)
        let marker: MarkdownListItem.Marker
        let content: String
        if ["- ", "* ", "+ ", "-\t", "*\t", "+\t"].contains(String(value.prefix(2))) {
            marker = .bullet
            content = String(value.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        } else {
            let digits = value.prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty, digits.count <= 9, let number = Int(digits) else { return nil }
            let suffix = value.dropFirst(digits.count)
            guard let delimiter = suffix.first, delimiter == "." || delimiter == ")",
                  suffix.dropFirst().first == " " || suffix.dropFirst().first == "\t" else { return nil }
            marker = .ordered(number)
            content = String(suffix.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        if marker == .bullet, content.count >= 3,
           ["[ ]", "[x]", "[X]"].contains(String(content.prefix(3))),
           content.count == 3 || content.dropFirst(3).first?.isWhitespace == true {
            return (indentation(line), .task(completed: content.prefix(3) != "[ ]"),
                    content.dropFirst(3).trimmingCharacters(in: .whitespaces))
        }
        return (indentation(line), marker, content)
    }

    private static func tableCells(_ line: String) -> [String]? {
        let value = line.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        var cells: [String] = []
        var cell = ""
        var escaped = false
        var separators = 0
        for character in value {
            if character == "|", !escaped {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
                separators += 1
            } else {
                cell.append(character)
            }
            escaped = character == "\\" && !escaped
        }
        guard separators > 0 else { return nil }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        if value.hasPrefix("|") { cells.removeFirst() }
        if value.hasSuffix("|"), cells.last == "" { cells.removeLast() }
        return cells.isEmpty ? nil : cells
    }

    private static func tableAlignments(_ line: String) -> [MarkdownTable.Alignment]? {
        guard let cells = tableCells(line) else { return nil }
        var alignments: [MarkdownTable.Alignment] = []
        for cell in cells {
            var middle = cell[...]
            if middle.first == ":" { middle = middle.dropFirst() }
            if middle.last == ":" { middle = middle.dropLast() }
            guard middle.count >= 3, middle.allSatisfy({ $0 == "-" }) else { return nil }
            alignments.append(cell.hasSuffix(":") ? (cell.hasPrefix(":") ? .center : .trailing) : .leading)
        }
        return alignments
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
