import Foundation

enum PrivacyRiskLevel: String, Equatable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    var displayText: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
}

struct PrivacyRiskAssessment: Equatable {
    var level: PrivacyRiskLevel
    var detectedSensitiveMatchCount: Int
    var redactionMatchCount: Int
    var invalidRedactionRuleCount: Int
    var hasImage: Bool
    var historyStoresContent: Bool
    var redactionEnabled: Bool

    static let low = PrivacyRiskAssessment(level: .low,
                                           detectedSensitiveMatchCount: 0,
                                           redactionMatchCount: 0,
                                           invalidRedactionRuleCount: 0,
                                           hasImage: false,
                                           historyStoresContent: false,
                                           redactionEnabled: false)

    var summaryText: String {
        "风险\(level.displayText) · 疑似敏感 \(detectedSensitiveMatchCount) 处 · 脱敏命中 \(redactionMatchCount) 处 · 图片\(hasImage ? "有" : "无") · \(historyStoresContent ? "历史保存正文" : "历史不保存正文")"
    }

    var diagnosticLine: String {
        let imageState = hasImage ? "yes" : "no"
        let historyState = historyStoresContent ? "yes" : "no"
        let redactionState = redactionEnabled ? "enabled" : "disabled"
        return "Privacy Risk: \(level.rawValue) (detected \(detectedSensitiveMatchCount), redaction \(redactionMatchCount), invalid rules \(invalidRedactionRuleCount), image \(imageState), history body \(historyState), redaction \(redactionState))"
    }

    var recoverySuggestion: String {
        var suggestions: [String] = []
        if invalidRedactionRuleCount > 0 {
            suggestions.append("修复失效脱敏规则")
        }
        if detectedSensitiveMatchCount > 0 && !redactionEnabled {
            suggestions.append("开启本地脱敏")
        }
        if historyStoresContent && detectedSensitiveMatchCount > 0 {
            suggestions.append("将历史改为仅元信息")
        }
        if level == .high || hasImage {
            suggestions.append("发送前预览并确认")
        }
        if hasImage {
            suggestions.append("确认图片不含敏感信息")
        }
        guard !suggestions.isEmpty else {
            return "当前风险较低,按需发送"
        }
        return suggestions.joined(separator: "; ")
    }

    static func assess(originalText: String,
                       redactionPreview: PrivacyRedactionPreview,
                       redactionEnabled: Bool,
                       hasImage: Bool,
                       saveHistoryEnabled: Bool,
                       historyContentStorage: HistoryContentStorage) -> PrivacyRiskAssessment {
        let defaultSensitiveMatches = PrivacyFilter.preview(text: originalText,
                                                            rules: PrivacyRedactionRule.defaults()).totalMatches
        let redactionMatches = redactionEnabled ? redactionPreview.totalMatches : 0
        let invalidRules = redactionEnabled ? redactionPreview.invalidReports.count : 0
        let detectedSensitiveMatches = max(defaultSensitiveMatches, redactionMatches)
        let historyStoresContent = saveHistoryEnabled && historyContentStorage == .full

        var score = 0
        if detectedSensitiveMatches > 0 { score += 2 }
        if detectedSensitiveMatches >= 3 { score += 1 }
        if hasImage { score += 1 }
        if !redactionEnabled && detectedSensitiveMatches > 0 { score += 1 }
        if historyStoresContent && detectedSensitiveMatches > 0 { score += 1 }
        if invalidRules > 0 { score += 1 }

        let level: PrivacyRiskLevel
        if score >= 4 {
            level = .high
        } else if score >= 2 {
            level = .medium
        } else {
            level = .low
        }

        return PrivacyRiskAssessment(level: level,
                                     detectedSensitiveMatchCount: detectedSensitiveMatches,
                                     redactionMatchCount: redactionMatches,
                                     invalidRedactionRuleCount: invalidRules,
                                     hasImage: hasImage,
                                     historyStoresContent: historyStoresContent,
                                     redactionEnabled: redactionEnabled)
    }
}

struct PrivacyPreviewRequirement: Equatable {
    enum Reason: String, Equatable {
        case notRequired = "not-required"
        case userEnabled = "user-enabled"
        case highPrivacyRisk = "high-privacy-risk"

        var displayText: String {
            switch self {
            case .notRequired: return "不需要"
            case .userEnabled: return "用户开启"
            case .highPrivacyRisk: return "高隐私风险"
            }
        }
    }

    var reason: Reason

    var isRequired: Bool {
        reason != .notRequired
    }

    func confirmationMessage(redactionEnabled: Bool) -> String {
        switch reason {
        case .highPrivacyRisk:
            return "检测到高隐私风险,本次需要确认即将发送给 AI 的内容。"
        case .userEnabled:
            return redactionEnabled
                ? "你已开启发送前预览,请确认本地脱敏命中情况和最终 Prompt。"
                : "你已开启发送前预览,请确认即将发送给 AI 的最终 Prompt。"
        case .notRequired:
            return redactionEnabled
                ? "请确认本地脱敏命中情况和最终 Prompt。"
                : "请确认即将发送给 AI 的最终 Prompt。"
        }
    }

    static func decide(userEnabled: Bool,
                       riskLevel: PrivacyRiskLevel) -> PrivacyPreviewRequirement {
        if riskLevel == .high {
            return PrivacyPreviewRequirement(reason: .highPrivacyRisk)
        }
        if userEnabled {
            return PrivacyPreviewRequirement(reason: .userEnabled)
        }
        return PrivacyPreviewRequirement(reason: .notRequired)
    }
}

struct PrivacySubmissionDiagnostic: Equatable {
    var originalCharacterCount: Int
    var submittedCharacterCount: Int
    var hasImage: Bool
    var redactionEnabled: Bool
    var redactionMatchCount: Int
    var invalidRedactionRuleCount: Int
    var saveHistoryEnabled: Bool
    var historyContentStorage: HistoryContentStorage = .full
    var previewRequired: Bool
    var previewReason: PrivacyPreviewRequirement.Reason = .notRequired
    var riskAssessment: PrivacyRiskAssessment = .low

    var historyStorageSummary: String {
        guard saveHistoryEnabled else { return "不保存" }
        if highRiskHistoryProtectionEnabled {
            return "\(HistoryContentStorage.metadataOnly.rawValue) (高风险保护)"
        }
        return historyContentStorage.rawValue
    }

    var highRiskHistoryProtectionEnabled: Bool {
        saveHistoryEnabled &&
        historyContentStorage == .full &&
        riskAssessment.level == .high
    }

    var contentExportProtectionEnabled: Bool {
        riskAssessment.level == .high
    }

    var effectiveHistoryContentStorage: HistoryContentStorage? {
        guard saveHistoryEnabled else { return nil }
        return highRiskHistoryProtectionEnabled ? .metadataOnly : historyContentStorage
    }

    var protectionSummaryText: String? {
        var parts: [String] = []
        if !saveHistoryEnabled {
            parts.append("不保存历史")
        } else if effectiveHistoryContentStorage == .metadataOnly {
            parts.append("历史仅元信息")
        }
        if contentExportProtectionEnabled {
            parts.append("导出省略正文")
        }
        guard !parts.isEmpty else { return nil }
        return "隐私保护：" + parts.joined(separator: "，")
    }

    var summaryLines: [String] {
        [
            "Submission Privacy:",
            "Original Characters: \(originalCharacterCount)",
            "Submitted Characters: \(submittedCharacterCount)",
            "Attached Image: \(hasImage ? "yes" : "no")",
            "Redaction Enabled: \(redactionEnabled ? "yes" : "no")",
            "Redaction Matches: \(redactionMatchCount)",
            "Invalid Redaction Rules: \(invalidRedactionRuleCount)",
            "Save History: \(saveHistoryEnabled ? "yes" : "no")",
            "History Content Storage: \(historyStorageSummary)",
            "Configured History Content Storage: \(saveHistoryEnabled ? historyContentStorage.rawValue : "不保存")",
            "Content Export Protected: \(contentExportProtectionEnabled ? "yes" : "no")",
            "Preview Required: \(previewRequired ? "yes" : "no")",
            "Preview Reason: \(previewReason.rawValue)",
            riskAssessment.diagnosticLine,
            "Privacy Recovery: \(riskAssessment.recoverySuggestion)"
        ]
    }

    var historyTags: [String] {
        var tags: [String] = []
        if redactionEnabled {
            tags.append(PrivacyHistoryTag.localRedaction)
        }
        if redactionMatchCount > 0 {
            tags.append(PrivacyHistoryTag.redactionMatched)
        }
        if invalidRedactionRuleCount > 0 {
            tags.append(PrivacyHistoryTag.invalidRedactionRule)
        }
        switch riskAssessment.level {
        case .high:
            tags.append(PrivacyHistoryTag.highPrivacyRisk)
        case .medium:
            tags.append(PrivacyHistoryTag.mediumPrivacyRisk)
        case .low:
            break
        }
        if previewRequired {
            tags.append(PrivacyHistoryTag.privacyPreview)
        }
        if !saveHistoryEnabled {
            tags.append(PrivacyHistoryTag.historyDisabled)
        }
        if saveHistoryEnabled && effectiveHistoryContentStorage == .metadataOnly {
            tags.append(PrivacyHistoryTag.metadataOnly)
        }
        return tags
    }
}

struct PrivacyPreparedSubmission: Equatable {
    var text: String
    var diagnostic: PrivacySubmissionDiagnostic
}

struct PrivacySubmissionPreview {
    var actionName: String
    var originalText: String
    var processedText: String
    var systemPrompt: String
    var userPrompt: String
    var hasImage: Bool
    var redactionEnabled: Bool
    var redactionReports: [PrivacyRedactionRuleReport]
    var saveHistoryEnabled: Bool
    var historyContentStorage: HistoryContentStorage

    init(action: AIAction,
         originalText: String,
         redactionPreview: PrivacyRedactionPreview,
         systemPrompt: String,
         redactionEnabled: Bool,
         hasImage: Bool,
         historyContentStorage: HistoryContentStorage = .full,
         userPromptOverride: String? = nil) {
        self.actionName = action.name
        self.originalText = originalText
        self.processedText = redactionPreview.output
        self.systemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.userPrompt = userPromptOverride ?? action.render(text: redactionPreview.output)
        self.hasImage = hasImage
        self.redactionEnabled = redactionEnabled
        self.redactionReports = redactionPreview.reports
        self.saveHistoryEnabled = action.saveHistory
        self.historyContentStorage = historyContentStorage
    }

    var totalRedactionMatches: Int {
        redactionReports.reduce(0) { $0 + $1.matchCount }
    }

    var invalidRedactionRuleCount: Int {
        redactionReports.filter { !$0.isValid }.count
    }

    var riskAssessment: PrivacyRiskAssessment {
        PrivacyRiskAssessment.assess(originalText: originalText,
                                     redactionPreview: PrivacyRedactionPreview(output: processedText,
                                                                               reports: redactionReports),
                                     redactionEnabled: redactionEnabled,
                                     hasImage: hasImage,
                                     saveHistoryEnabled: saveHistoryEnabled,
                                     historyContentStorage: historyContentStorage)
    }

    func previewRequirement(userPreferenceEnabled: Bool) -> PrivacyPreviewRequirement {
        PrivacyPreviewRequirement.decide(userEnabled: userPreferenceEnabled,
                                         riskLevel: riskAssessment.level)
    }

    var summaryText: String {
        summaryText(previewRequirement: nil)
    }

    func summaryText(previewRequirement: PrivacyPreviewRequirement?) -> String {
        let redactionState: String
        if redactionEnabled {
            redactionState = "已启用,命中 \(totalRedactionMatches) 处,失效规则 \(invalidRedactionRuleCount) 条"
        } else {
            redactionState = "未启用"
        }
        var lines = [
            "动作: \(actionName)",
            "原文字符数: \(originalText.count)",
            "发送字符数: \(processedText.count)",
            "本地脱敏: \(redactionState)",
            "隐私风险: \(riskAssessment.summaryText)",
            "隐私建议: \(riskAssessment.recoverySuggestion)",
            "保存历史: \(saveHistoryEnabled ? "是" : "否")",
            "历史内容: \(diagnostic(previewRequired: false).historyStorageSummary)",
            "附加内容: \(hasImage ? "1 张图片" : "无")"
        ]
        if let previewRequirement {
            lines.insert("预览原因: \(previewRequirement.reason.displayText)", at: 5)
        }
        return lines.joined(separator: "\n")
    }

    func diagnostic(previewRequired: Bool) -> PrivacySubmissionDiagnostic {
        let reason: PrivacyPreviewRequirement.Reason = previewRequired ? .userEnabled : .notRequired
        return diagnostic(previewRequirement: PrivacyPreviewRequirement(reason: reason))
    }

    func diagnostic(previewRequirement: PrivacyPreviewRequirement) -> PrivacySubmissionDiagnostic {
        PrivacySubmissionDiagnostic(originalCharacterCount: originalText.count,
                                    submittedCharacterCount: processedText.count,
                                    hasImage: hasImage,
                                    redactionEnabled: redactionEnabled,
                                    redactionMatchCount: totalRedactionMatches,
                                    invalidRedactionRuleCount: invalidRedactionRuleCount,
                                    saveHistoryEnabled: saveHistoryEnabled,
                                    historyContentStorage: historyContentStorage,
                                    previewRequired: previewRequirement.isRequired,
                                    previewReason: previewRequirement.reason,
                                    riskAssessment: riskAssessment)
    }

    var redactionReportText: String {
        guard redactionEnabled else { return "本地脱敏未启用。" }
        guard !redactionReports.isEmpty else { return "没有配置脱敏规则。" }
        return redactionReports.map { report in
            "- \(report.ruleName): \(report.statusText)"
        }.joined(separator: "\n")
    }

    var contentText: String {
        contentText(previewRequirement: nil)
    }

    func contentText(previewRequirement: PrivacyPreviewRequirement?) -> String {
        let systemText = systemPrompt.isEmpty ? "(空)" : systemPrompt
        return """
        \(summaryText(previewRequirement: previewRequirement))

        脱敏规则:
        \(redactionReportText)

        System Prompt:
        \(systemText)

        User Prompt:
        \(userPrompt)
        """
    }
}
