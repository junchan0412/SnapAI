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
                name: "API Key 与访问令牌",
                pattern: #"(?i)(?:\bsk(?:-[A-Z0-9]+)+\b|\bgh[pousr]_[A-Z0-9_]{20,}\b|\bgithub_pat_[A-Z0-9_]{20,}\b|\bxox[baprs]-[A-Z0-9-]{20,}\b|\bAKIA[0-9A-Z]{16}\b|\bAIza[0-9A-Z_-]{20,}\b|[?&](?:x-api-key|api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|client[_-]?secret|token|secret|password)=[^&#\s]+|\b(?:api[_-]?key|token|secret|password)[_:\-= ]+[A-Z0-9][A-Z0-9._-]{11,})"#,
                replacement: "[密钥]"
            ),
            PrivacyRedactionRule(
                name: "私钥与 JWT",
                pattern: #"(?is)(?:-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----|\beyJ[A-Z0-9_-]{10,}\.[A-Z0-9_-]{10,}\.[A-Z0-9_-]{10,}\b)"#,
                replacement: "[密钥]"
            )
        ]
    }
}

struct PrivacyRedactionRuleReport: Equatable {
    var ruleID: String
    var ruleName: String
    var isEnabled: Bool
    var isValid: Bool
    var matchCount: Int
    var errorMessage: String?
    var warningMessage: String? = nil

    var statusText: String {
        if !isEnabled { return "已停用" }
        if let errorMessage { return "规则错误: \(errorMessage)" }
        let base = matchCount == 0 ? "未命中" : "命中 \(matchCount) 处"
        guard let warningMessage else { return base }
        return "\(base); \(warningMessage)"
    }
}

struct PrivacyRedactionPreview: Equatable {
    var output: String
    var reports: [PrivacyRedactionRuleReport]

    var invalidReports: [PrivacyRedactionRuleReport] {
        reports.filter { !$0.isValid }
    }

    var totalMatches: Int {
        reports.reduce(0) { $0 + $1.matchCount }
    }
}

enum PrivacyFilter {
    static let maxPatternLength = 1_000
    static let maxReplacementLength = 200
    static let maxRuleNameLength = 80
    static let defaultSampleText = """
    联系我 test@example.com 或 13800138000
    API Key: sk-live-secret-value-1234567890
    回调 https://example.test/callback?access_token=visible-access-token&ok=true
    """
    static let defaultSampleEditorLineHeight: Double = 20
    static let defaultSampleEditorVerticalPadding: Double = 28

    static var defaultSampleLineCount: Int {
        max(1, defaultSampleText.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    static var defaultSampleEditorHeight: Double {
        max(58, Double(defaultSampleLineCount) * defaultSampleEditorLineHeight + defaultSampleEditorVerticalPadding)
    }

    static func apply(to text: String, rules: [PrivacyRedactionRule]) -> String {
        preview(text: text, rules: rules).output
    }

    static func preview(text: String, rules: [PrivacyRedactionRule]) -> PrivacyRedactionPreview {
        var result = text
        var reports: [PrivacyRedactionRuleReport] = []
        for rule in rules where rule.isEnabled && !rule.pattern.isEmpty {
            if let validationError = validatePattern(rule.pattern) {
                reports.append(PrivacyRedactionRuleReport(ruleID: rule.id,
                                                          ruleName: displayName(for: rule),
                                                          isEnabled: rule.isEnabled,
                                                          isValid: false,
                                                          matchCount: 0,
                                                          errorMessage: validationError))
                continue
            }

            let regex: NSRegularExpression
            do {
                regex = try NSRegularExpression(pattern: rule.pattern,
                                                options: [.caseInsensitive])
            } catch {
                reports.append(PrivacyRedactionRuleReport(ruleID: rule.id,
                                                          ruleName: displayName(for: rule),
                                                          isEnabled: rule.isEnabled,
                                                          isValid: false,
                                                          matchCount: 0,
                                                          errorMessage: error.localizedDescription))
                continue
            }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            let matchCount = regex.numberOfMatches(in: result, options: [], range: range)
            // 转义替换文本,避免其中的 $ / \ 被当作捕获组引用
            let replacement = safeReplacement(rule.replacement)
            let template = NSRegularExpression.escapedTemplate(for: replacement.value)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: template
            )
            reports.append(PrivacyRedactionRuleReport(ruleID: rule.id,
                                                      ruleName: displayName(for: rule),
                                                      isEnabled: rule.isEnabled,
                                                      isValid: true,
                                                      matchCount: matchCount,
                                                      errorMessage: nil,
                                                      warningMessage: replacement.wasTruncated ? "替换文本已截断" : nil))
        }
        for rule in rules where !rule.isEnabled || rule.pattern.isEmpty {
            reports.append(PrivacyRedactionRuleReport(ruleID: rule.id,
                                                      ruleName: displayName(for: rule),
                                                      isEnabled: rule.isEnabled,
                                                      isValid: !rule.isEnabled || !rule.pattern.isEmpty,
                                                      matchCount: 0,
                                                      errorMessage: rule.pattern.isEmpty && rule.isEnabled ? "正则表达式为空" : nil))
        }
        return PrivacyRedactionPreview(output: result, reports: reports)
    }

    static func validatePattern(_ pattern: String) -> String? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "正则表达式为空" }
        guard trimmed.count <= maxPatternLength else {
            return "正则表达式过长,请控制在 \(maxPatternLength) 个字符以内"
        }
        if containsHighRiskWildcardQuantifier(trimmed) {
            return "正则表达式包含高风险通配嵌套量词,可能导致界面卡顿"
        }
        do {
            _ = try NSRegularExpression(pattern: trimmed, options: [.caseInsensitive])
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func displayName(for rule: PrivacyRedactionRule) -> String {
        MarkdownExportSafety.metadata(rule.name,
                                      fallback: "未命名规则",
                                      maxLength: maxRuleNameLength)
    }

    private static func safeReplacement(_ replacement: String) -> (value: String, wasTruncated: Bool) {
        guard replacement.count > maxReplacementLength else {
            return (replacement, false)
        }
        return (String(replacement.prefix(maxReplacementLength)), true)
    }

    private static func containsHighRiskWildcardQuantifier(_ pattern: String) -> Bool {
        let riskyPatterns = [
            #"\((?:\\.|[^()\\])*\.[+*](?:\\.|[^()\\])*\)(?:[+*]|\{)"#,
            #"\(\?:?(?:\\.|[^()\\])*\.[+*](?:\\.|[^()\\])*\)(?:[+*]|\{)"#
        ]
        return riskyPatterns.contains { regex in
            pattern.range(of: regex, options: .regularExpression) != nil
        }
    }
}
