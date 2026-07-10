import Carbon.HIToolbox
import Foundation

/// AI 协议类型
enum APIProtocol: String, Codable, CaseIterable, Identifiable {
    case openAI = "OpenAI 兼容"
    case anthropic = "Anthropic 原生"
    var id: String { rawValue }
}

/// 打字机动画速度
public enum TypewriterSpeed: String, Codable, CaseIterable, Identifiable {
    case off = "关闭"
    case slow = "慢"
    case normal = "标准"
    case fast = "快"
    public var id: String { rawValue }

    /// 每次 tick 揭示的字符数
    var charsPerTick: Int {
        switch self {
        case .off: return 0       // 0 表示不走打字机,直接整段显示
        case .slow: return 1
        case .normal: return 2
        case .fast: return 5
        }
    }

    /// tick 间隔(秒)
    var tickInterval: TimeInterval {
        switch self {
        case .off: return 0
        case .slow: return 0.03
        case .normal: return 0.012
        case .fast: return 0.008
        }
    }
}

/// AI 自动路由偏好。
public enum AIRoutingPreference: String, Codable, CaseIterable, Identifiable {
    case fastest = "最快"
    case balanced = "均衡"
    case quality = "最佳质量"

    public var id: String { rawValue }

    var description: String {
        switch self {
        case .fastest:
            return "优先低延迟和低成本模型"
        case .balanced:
            return "兼顾速度、成本和任务适配"
        case .quality:
            return "优先长上下文、推理和复杂任务能力"
        }
    }
}

/// 历史记录内容保存策略。
enum HistoryContentStorage: String, Codable, CaseIterable, Identifiable {
    case full = "完整保存"
    case metadataOnly = "仅元信息"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .full:
            return "保存原文和结果,便于搜索与回看"
        case .metadataOnly:
            return "只保存动作、模型、时间和隐私标签"
        }
    }
}

struct WorkModeBehavior: Equatable {
    var privacyPreviewEnabled: Bool
    var redactionEnabled: Bool
    var historyContentStorage: HistoryContentStorage
    var autoRouteEnabled: Bool
    var fallbackEnabled: Bool
    var routingPreference: AIRoutingPreference
}

public enum WorkModePreset: String, Codable, CaseIterable, Identifiable {
    case standard
    case privacy
    case speed
    case quality

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "标准模式"
        case .privacy: return "隐私模式"
        case .speed: return "极速模式"
        case .quality: return "质量模式"
        }
    }

    var shortTitle: String {
        switch self {
        case .standard: return "标准"
        case .privacy: return "隐私"
        case .speed: return "极速"
        case .quality: return "质量"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: return "slider.horizontal.3"
        case .privacy: return "hand.raised"
        case .speed: return "bolt"
        case .quality: return "sparkles"
        }
    }

    var summary: String {
        switch self {
        case .standard:
            return "平衡日常效率与完整历史记录。"
        case .privacy:
            return "发送前确认、本地脱敏,历史仅保存元信息。"
        case .speed:
            return "自动路由到低延迟模型,减少确认步骤。"
        case .quality:
            return "自动路由并优先质量,适合长文和复杂任务。"
        }
    }

    var keywords: String {
        switch self {
        case .standard:
            return "work mode standard default balanced settings 模式 标准 默认 均衡"
        case .privacy:
            return "work mode privacy preview redaction metadata history safe 隐私 预览 脱敏 元信息"
        case .speed:
            return "work mode speed fastest route low latency quick 极速 快速 路由 低延迟"
        case .quality:
            return "work mode quality best route reasoning long context 质量 最佳 长文 推理"
        }
    }

    var behavior: WorkModeBehavior {
        switch self {
        case .standard:
            return WorkModeBehavior(privacyPreviewEnabled: false,
                                    redactionEnabled: false,
                                    historyContentStorage: .full,
                                    autoRouteEnabled: false,
                                    fallbackEnabled: true,
                                    routingPreference: .balanced)
        case .privacy:
            return WorkModeBehavior(privacyPreviewEnabled: true,
                                    redactionEnabled: true,
                                    historyContentStorage: .metadataOnly,
                                    autoRouteEnabled: true,
                                    fallbackEnabled: true,
                                    routingPreference: .balanced)
        case .speed:
            return WorkModeBehavior(privacyPreviewEnabled: false,
                                    redactionEnabled: false,
                                    historyContentStorage: .full,
                                    autoRouteEnabled: true,
                                    fallbackEnabled: true,
                                    routingPreference: .fastest)
        case .quality:
            return WorkModeBehavior(privacyPreviewEnabled: false,
                                    redactionEnabled: false,
                                    historyContentStorage: .full,
                                    autoRouteEnabled: true,
                                    fallbackEnabled: true,
                                    routingPreference: .quality)
        }
    }
}

struct ContextStatusSummary: Equatable {
    var profileCount: Int
    var usableProfileCount: Int
    var activeProfileName: String
    var activeContextCharacterCount: Int
    var globalSystemPromptCharacterCount: Int
    var effectiveSystemPromptCharacterCount: Int

    var hasActiveContext: Bool {
        activeContextCharacterCount > 0
    }

    var activeProfileDisplayName: String {
        activeProfileName.isEmpty ? "无" : activeProfileName
    }

    var shareableActiveContextState: String {
        hasActiveContext ? "set" : "none"
    }

    var shareableActiveProfileNameCharacterCount: Int {
        hasActiveContext ? activeProfileName.count : 0
    }

    static func make(settings: AppSettings) -> ContextStatusSummary {
        let usableProfiles = settings.contextProfiles.filter {
            $0.isEnabled && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let activeProfile = settings.activeContextProfile
        let activeName = activeProfile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let activeCharacters = activeProfile?.content.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
        return ContextStatusSummary(
            profileCount: settings.contextProfiles.count,
            usableProfileCount: usableProfiles.count,
            activeProfileName: activeName,
            activeContextCharacterCount: activeCharacters,
            globalSystemPromptCharacterCount: settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count,
            effectiveSystemPromptCharacterCount: settings.effectiveSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count
        )
    }
}

/// 一个可配置的快捷键(键码 + 修饰键)
struct HotKeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon 修饰键掩码 (cmdKey/optionKey/...)

    static let askDefault = HotKeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey))
    static let translateDefault = HotKeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey))
    static let polishDefault = HotKeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(optionKey))
    static let summarizeDefault = HotKeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey))
    static let explainCodeDefault = HotKeyCombo(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(optionKey))

    /// 人类可读描述,如 "⌥A"
    var displayString: String {
        if modifiers == 0 { return "未设置" }
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += KeyCodeMap.name(for: keyCode)
        return s
    }
}

/// 键码 → 名称 的最小映射(用于显示快捷键)
enum KeyCodeMap {
    static func name(for keyCode: UInt32) -> String {
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋",
            kVK_Delete: "Delete", kVK_ForwardDelete: "⌦"
        ]
        return map[Int(keyCode)] ?? "Key\(keyCode)"
    }
}
