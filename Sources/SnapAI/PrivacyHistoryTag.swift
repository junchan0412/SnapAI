import Foundation

enum PrivacyHistoryTag {
    static let localRedaction = "本地脱敏"
    static let redactionMatched = "脱敏命中"
    static let invalidRedactionRule = "脱敏规则异常"
    static let mediumPrivacyRisk = "隐私风险中"
    static let highPrivacyRisk = "隐私风险高"
    static let privacyPreview = "隐私预览"
    static let historyDisabled = "不保存历史"
    static let metadataOnly = "仅元信息"
    static let sourceTruncated = "原文截断"
    static let outputTruncated = "结果截断"

    static let prioritizedForHistoryExport = [
        localRedaction,
        redactionMatched,
        invalidRedactionRule,
        highPrivacyRisk,
        mediumPrivacyRisk,
        privacyPreview,
        metadataOnly
    ]
}
