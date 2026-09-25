import Foundation
import FoundationModels

/// Apple 端侧模型适配:macOS 26+ FoundationModels,离线、免费、不出本机。
///
/// 设计约束:
/// 1. 可用性三态经 `availability()` 暴露,UI(供应商卡片)据此展示
///    "可用/未开启 Apple Intelligence/设备不支持",绝不静默失败。
/// 2. 非流式单次 `respond` —— 端侧模型只用于短问答/改写/总结等轻任务;
///    长文本与视觉任务由 ModelCapability 降级提示引导回云端模型。
/// 3. macOS 26 以下编译通过、运行时不可用(SDK 弱链接经 #available 守卫)。
package enum AppleOnDeviceModel {
    package static let providerName = "Apple 本机模型"
    package static let modelName = "system-default"
    /// 占位端点:不产生真实网络请求,仅用于满足 providerReadiness 的 URL 校验。
    package static let placeholderBaseURL = "apple-foundation-models://local"

    package enum Availability: Equatable {
        /// 可用(available)
        case available
        /// 设备不支持 Apple Intelligence
        case deviceNotEligible
        /// 未开启 Apple Intelligence
        case appleIntelligenceNotEnabled
        /// 模型未就绪(下载中/后台准备中)
        case modelNotReady
        /// macOS 26 以下,无端侧模型
        case unsupportedOS
        case other(String)

        package var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }

        package var displayText: String {
            switch self {
            case .available: return "可用"
            case .deviceNotEligible: return "此设备不支持 Apple Intelligence"
            case .appleIntelligenceNotEnabled: return "未开启 Apple Intelligence,请在系统设置中开启"
            case .modelNotReady: return "端侧模型准备中,稍后重试"
            case .unsupportedOS: return "需要 macOS 26 及以上"
            case .other(let message): return message
            }
        }
    }

    package static func availability() -> Availability {
        guard #available(macOS 26, *) else { return .unsupportedOS }
        return foundationAvailability()
    }

    @available(macOS 26, *)
    private static func foundationAvailability() -> Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .other("端侧模型暂不可用")
        }
    }

    /// 单次问答。调用方在后台线程调用;端侧推理同步返回。
    @available(macOS 26, *)
    package static func respond(to prompt: String,
                                systemPrompt: String? = nil) async throws -> String {
        var instructions: String?
        if let systemPrompt, !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            instructions = systemPrompt
        }
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content
    }

    /// 供应商预设对应的端侧能力画像:无视觉、短上下文、快速省钱,用于路由降级提示。
    package static func capability() -> ModelCapability {
        ModelCapability(supportsVision: false,
                        supportsReasoning: false,
                        contextTokens: 4_096,
                        isFast: true,
                        isEconomical: true,
                        isCodeCapable: false)
    }
}
