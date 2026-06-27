import Foundation

struct PrivacyRedactionRule: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var pattern: String
    var replacement: String
    var isEnabled: Bool = true

    static func defaults() -> [PrivacyRedactionRule] {
        [
            PrivacyRedactionRule(
                name: "邮箱地址",
                pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                replacement: "[邮箱]"
            ),
            PrivacyRedactionRule(
                name: "手机号",
                pattern: #"(?<!\d)(?:\+?86[- ]?)?1[3-9]\d{9}(?!\d)"#,
                replacement: "[手机号]"
            ),
            PrivacyRedactionRule(
                name: "疑似 API Key",
                pattern: #"(?i)\b(?:sk|api|key|token|secret)[-_]?[a-z0-9]{12,}\b"#,
                replacement: "[密钥]"
            )
        ]
    }
}

enum PrivacyFilter {
    static func apply(to text: String, rules: [PrivacyRedactionRule]) -> String {
        var result = text
        for rule in rules where rule.isEnabled && !rule.pattern.isEmpty {
            guard let regex = try? NSRegularExpression(
                pattern: rule.pattern,
                options: [.caseInsensitive]
            ) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            // 转义替换文本,避免其中的 $ / \ 被当作捕获组引用
            let template = NSRegularExpression.escapedTemplate(for: rule.replacement)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: template
            )
        }
        return result
    }
}
