import Foundation

enum SelectionSourceKind: String, Codable, Equatable {
    case browser = "browser"
    case codeEditor = "code-editor"
    case terminal = "terminal"
    case documentEditor = "document-editor"
    case messaging = "messaging"
    case mail = "mail"
    case pdfReader = "pdf-reader"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .browser: return "浏览器"
        case .codeEditor: return "代码编辑器"
        case .terminal: return "终端"
        case .documentEditor: return "文档编辑器"
        case .messaging: return "聊天工具"
        case .mail: return "邮件客户端"
        case .pdfReader: return "PDF/文档阅读器"
        case .unknown: return "未知应用"
        }
    }

    var promptHint: String {
        switch self {
        case .browser:
            return "选中文字来自浏览器页面,请注意网页内容可能包含片段化上下文。"
        case .codeEditor:
            return "选中文字来自代码编辑器,请优先按代码、配置或技术文档语境理解。"
        case .terminal:
            return "选中文字来自终端,请优先按命令输出、日志或错误信息语境理解。"
        case .documentEditor:
            return "选中文字来自文档编辑器,请优先按写作、办公文档或长文语境理解。"
        case .messaging:
            return "选中文字来自聊天工具,请优先按对话片段语境理解,保持语气自然。"
        case .mail:
            return "选中文字来自邮件客户端,请优先按邮件往来语境理解,注意礼貌和上下文承接。"
        case .pdfReader:
            return "选中文字来自 PDF 或文档阅读器,请优先按资料摘录或引用片段语境理解。"
        case .unknown:
            return "选中文字来自未知应用,请只基于文本本身和用户配置的上下文判断。"
        }
    }
}

struct SelectionSourceContext: Equatable {
    var kind: SelectionSourceKind
    var appName: String?

    var sanitizedAppName: String {
        MarkdownExportSafety.metadata(appName,
                                      fallback: "unknown",
                                      maxLength: 80)
    }

    var diagnosticLine: String {
        "Selection Source: kind=\(kind.rawValue), app=\(sanitizedAppName)"
    }

    var promptPrefix: String {
        """
        [SnapAI 选区来源]
        - 来源类型: \(kind.displayName)
        - 上下文提示: \(kind.promptHint)

        [用户选中的内容]
        """
    }

    static func make(appName: String?) -> SelectionSourceContext {
        SelectionSourceContext(kind: classify(appName: appName), appName: appName)
    }

    static func classify(appName: String?) -> SelectionSourceKind {
        let normalized = appName?
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else { return .unknown }

        if containsAny(normalized, ["safari", "chrome", "chromium", "firefox", "arc", "edge", "brave", "browser"]) {
            return .browser
        }
        if containsAny(normalized, ["xcode", "visual studio code", "vscode", "code", "cursor", "zed", "sublime", "intellij", "webstorm", "pycharm", "goland", "android studio"]) {
            return .codeEditor
        }
        if containsAny(normalized, ["terminal", "iterm", "ghostty", "warp", "kitty", "alacritty"]) {
            return .terminal
        }
        if containsAny(normalized, ["pages", "word", "textedit", "notes", "notion", "obsidian", "bear", "typora", "ulysses"]) {
            return .documentEditor
        }
        if containsAny(normalized, ["slack", "discord", "telegram", "wechat", "weixin", "微信", "feishu", "lark", "飞书", "teams", "messages"]) {
            return .messaging
        }
        if containsAny(normalized, ["mail", "outlook", "spark", "thunderbird"]) {
            return .mail
        }
        if containsAny(normalized, ["preview", "adobe acrobat", "pdf", "skim", "pdf expert"]) {
            return .pdfReader
        }
        return .unknown
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
