import Foundation

public struct ResultRecoverySettingsDescriptor: Equatable {
    public var title: String
    public var compactTitle: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: String
}

public struct ResultRecoveryRetryDescriptor: Equatable {
    public var title: String
    public var compactTitle: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: String
}

public enum ResultRecoveryPrimaryAction: Equatable {
    case retry
    case settings
}

public enum ResultRecoveryCommand {
    public static var openAISettingsTitle: String { openAISettingsDescriptor(recoveryCode: nil).title }
    public static var openAISettingsCompactTitle: String { openAISettingsDescriptor(recoveryCode: nil).compactTitle }
    public static var openAISettingsSubtitle: String { openAISettingsDescriptor(recoveryCode: nil).subtitle }
    public static var openAISettingsSystemImage: String { openAISettingsDescriptor(recoveryCode: nil).systemImage }
    public static var openAISettingsKeywords: String { openAISettingsDescriptor(recoveryCode: nil).keywords }

    public static func openAISettingsDescriptor(recoveryCode: String?) -> ResultRecoverySettingsDescriptor {
        switch normalizedRecoveryCode(recoveryCode) {
        case "missing-provider", "no-candidate-routes":
            return ResultRecoverySettingsDescriptor(
                title: "添加 AI 供应商",
                compactTitle: "添加供应商",
                subtitle: "启用供应商、填写 API Key,并配置可用模型",
                systemImage: "plus.circle",
                keywords: "\(baseKeywords) add provider enable missing no candidate 添加 供应商 启用 无可用"
            )
        case "missing-model", "route-unavailable":
            return ResultRecoverySettingsDescriptor(
                title: "选择可用模型",
                compactTitle: "选择模型",
                subtitle: "启用或添加模型,并设为当前模型",
                systemImage: "checklist.checked",
                keywords: "\(baseKeywords) select model enable missing unavailable 选择 模型 启用 不可用"
            )
        case "api-key":
            return ResultRecoverySettingsDescriptor(
                title: "填写 API Key",
                compactTitle: "API Key",
                subtitle: "重新填写密钥,并确认供应商账号可用",
                systemImage: "key",
                keywords: "\(baseKeywords) api key token secret authentication unauthorized 密钥 认证"
            )
        case "base-url":
            return ResultRecoverySettingsDescriptor(
                title: "检查 Base URL",
                compactTitle: "Base URL",
                subtitle: "确认端点格式正确;远程服务请使用 HTTPS",
                systemImage: "link",
                keywords: "\(baseKeywords) base url endpoint https invalid 端点 地址"
            )
        case "model-not-found":
            return ResultRecoverySettingsDescriptor(
                title: "检查模型名称",
                compactTitle: "模型名称",
                subtitle: "确认模型名称和 Base URL 匹配当前供应商",
                systemImage: "text.magnifyingglass",
                keywords: "\(baseKeywords) model not found name 404 模型 名称 未找到"
            )
        default:
            return ResultRecoverySettingsDescriptor(
                title: "打开 AI 设置",
                compactTitle: "AI 设置",
                subtitle: "检查供应商、API Key、模型和 Base URL",
                systemImage: "gearshape.2",
                keywords: baseKeywords
            )
        }
    }

    public static func retryDescriptor(recoveryCode: String?) -> ResultRecoveryRetryDescriptor {
        switch normalizedRecoveryCode(recoveryCode) {
        case "missing-provider", "missing-model", "no-candidate-routes", "route-unavailable", "api-key", "base-url", "model-not-found":
            return ResultRecoveryRetryDescriptor(
                title: "配置后重试",
                compactTitle: "配置后重试",
                subtitle: "先修复 AI 设置,再重新发送请求",
                systemImage: "arrow.clockwise.circle",
                keywords: "\(retryKeywords) settings config fix provider model api key base url 配置后 重试 修复 设置"
            )
        case "context-limit", "payload-too-large", "invalid-request":
            return ResultRecoveryRetryDescriptor(
                title: "调整后重试",
                compactTitle: "调整后重试",
                subtitle: "缩短内容、压缩图片或切换合适模型后再试",
                systemImage: "slider.horizontal.3",
                keywords: "\(retryKeywords) adjust context payload model 调整 缩短 压缩 重试"
            )
        case "rate-limit":
            return ResultRecoveryRetryDescriptor(
                title: "稍后重试",
                compactTitle: "稍后重试",
                subtitle: "触发限速后等待片刻,或切换备用供应商",
                systemImage: "timer",
                keywords: "\(retryKeywords) rate limit later retry 限速 稍后 重试"
            )
        case "network", "provider-service", "cancelled":
            return ResultRecoveryRetryDescriptor(
                title: "重试请求",
                compactTitle: "重试",
                subtitle: "网络或供应商临时异常时可直接重试",
                systemImage: "arrow.clockwise",
                keywords: retryKeywords
            )
        case "quota", "permission":
            return ResultRecoveryRetryDescriptor(
                title: "处理后重试",
                compactTitle: "处理后重试",
                subtitle: "处理账号额度或权限后再重新发送请求",
                systemImage: "person.crop.circle.badge.exclamationmark",
                keywords: "\(retryKeywords) quota permission account billing 额度 权限 账号 重试"
            )
        default:
            return ResultRecoveryRetryDescriptor(
                title: "重新生成",
                compactTitle: "重试",
                subtitle: "使用当前原文和动作重新发送",
                systemImage: "arrow.clockwise",
                keywords: retryKeywords
            )
        }
    }

    public static func primaryAction(recoveryCode: String?) -> ResultRecoveryPrimaryAction {
        switch normalizedRecoveryCode(recoveryCode) {
        case "missing-provider", "missing-model", "no-candidate-routes", "route-unavailable", "api-key", "base-url", "model-not-found":
            return .settings
        default:
            return .retry
        }
    }

    private static let baseKeywords = "result recovery ai settings provider api key model base url fix 请求 恢复 修复 AI 设置 供应商 模型 密钥"
    private static let retryKeywords = "result regenerate retry request again 重新 生成 重试 请求"

    private static func normalizedRecoveryCode(_ code: String?) -> String {
        code?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }
}
