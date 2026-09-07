import Foundation

package enum PrivacyHistoryTag {
    package static let localRedaction = "本地脱敏"
    package static let redactionMatched = "脱敏命中"
    package static let invalidRedactionRule = "脱敏规则异常"
    package static let mediumPrivacyRisk = "隐私风险中"
    package static let highPrivacyRisk = "隐私风险高"
    package static let privacyPreview = "隐私预览"
    package static let historyDisabled = "不保存历史"
    package static let metadataOnly = "仅元信息"
    package static let sourceTruncated = "原文截断"
    package static let outputTruncated = "结果截断"

    package static let prioritizedForHistoryExport = [
        localRedaction,
        redactionMatched,
        invalidRedactionRule,
        highPrivacyRisk,
        mediumPrivacyRisk,
        privacyPreview,
        metadataOnly
    ]
}
