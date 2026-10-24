import Foundation

public struct MarkdownCodeToken: Equatable {
    public enum Kind: Equatable { case plain, comment, string, number, keyword }
    public var text: String
    public var kind: Kind
}

public enum MarkdownCodeHighlighter {
    private static let cPattern = makePattern(comment: #"//[^\n]*|/\*[\s\S]*?\*/"#)
    private static let hashPattern = makePattern(comment: #"#[^\n]*"#)
    private static let sqlPattern = makePattern(comment: #"--[^\n]*|/\*[\s\S]*?\*/"#)
    private static let jsonPattern = makePattern(comment: #"(?!)"#)
    private static let commonKeywords: Set<String> = [
        "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "default",
        "defer", "do", "else", "enum", "export", "false", "final", "for", "from", "func", "function",
        "guard", "if", "implements", "import", "in", "init", "interface", "internal", "is", "let",
        "new", "nil", "null", "private", "protected", "protocol", "public", "return", "self",
        "static", "struct", "super", "switch", "this", "throw", "throws", "true", "try", "type",
        "typealias", "typeof", "undefined", "var", "void", "while"
    ]
    private static let pythonKeywords: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif",
        "else", "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is",
        "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return", "True", "try", "while",
        "with", "yield"
    ]
    private static let sqlKeywords: Set<String> = [
        "select", "from", "where", "join", "left", "right", "inner", "outer", "on", "as", "and", "or",
        "not", "null", "is", "in", "group", "by", "order", "having", "limit", "offset", "insert",
        "into", "values", "update", "set", "delete", "create", "table", "drop", "distinct", "union"
    ]
    private static let shellKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "in", "do", "done", "case", "esac", "while",
        "function", "export", "local", "return"
    ]

    public static func tokens(_ code: String, language: String?) -> [MarkdownCodeToken] {
        let language = language?.split(whereSeparator: \.isWhitespace).first?.lowercased() ?? ""
        let expression: NSRegularExpression
        let keywords: Set<String>
        switch language {
        case "swift", "js", "javascript", "jsx", "ts", "typescript", "tsx", "c", "cpp", "c++",
             "csharp", "cs", "java", "go", "rust", "kotlin":
            expression = cPattern
            keywords = commonKeywords
        case "py", "python":
            expression = hashPattern
            keywords = pythonKeywords
        case "sh", "bash", "zsh", "shell":
            expression = hashPattern
            keywords = shellKeywords
        case "sql":
            expression = sqlPattern
            keywords = sqlKeywords
        case "json":
            expression = jsonPattern
            keywords = ["true", "false", "null"]
        default:
            return [MarkdownCodeToken(text: code, kind: .plain)]
        }
        let source = code as NSString
        var tokens: [MarkdownCodeToken] = []
        var cursor = 0
        func append(_ text: String, _ kind: MarkdownCodeToken.Kind) {
            guard !text.isEmpty else { return }
            if tokens.last?.kind == kind {
                tokens[tokens.count - 1].text += text
            } else {
                tokens.append(MarkdownCodeToken(text: text, kind: kind))
            }
        }
        expression.enumerateMatches(in: code, range: NSRange(location: 0, length: source.length)) { match, _, _ in
            guard let match else { return }
            if match.range.location > cursor {
                append(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), .plain)
            }
            let text = source.substring(with: match.range)
            let kind: MarkdownCodeToken.Kind
            if match.range(at: 1).location != NSNotFound { kind = .comment }
            else if match.range(at: 2).location != NSNotFound { kind = .string }
            else if match.range(at: 3).location != NSNotFound { kind = .number }
            else if keywords.contains(language == "sql" ? text.lowercased() : text) { kind = .keyword }
            else { kind = .plain }
            append(text, kind)
            cursor = NSMaxRange(match.range)
        }
        if cursor < source.length {
            append(source.substring(from: cursor), .plain)
        }
        return tokens
    }

    private static func makePattern(comment: String) -> NSRegularExpression {
        let pattern = "(" + comment + #")|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)|(\b\d+(?:\.\d+)?\b)|\b[A-Za-z_][A-Za-z_0-9]*\b"#
        return try! NSRegularExpression(pattern: pattern)
    }
}
