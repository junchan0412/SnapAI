import Foundation
import Carbon.HIToolbox

/// 翻译/输出目标语言
enum TargetLanguage: String, Codable, CaseIterable, Identifiable {
    case auto = "自动(中英互译)"
    case chinese = "简体中文"
    case english = "英语"
    case japanese = "日语"
    case korean = "韩语"
    case french = "法语"
    case german = "德语"
    case spanish = "西班牙语"
    var id: String { rawValue }

    /// 注入 prompt 的指令片段
    var instruction: String {
        switch self {
        case .auto: return "如果原文是中文,翻译成自然流畅的英文;否则翻译成简体中文"
        case .chinese: return "翻译成简体中文"
        case .english: return "翻译成自然流畅的英语"
        case .japanese: return "翻译成日语"
        case .korean: return "翻译成韩语"
        case .french: return "翻译成法语"
        case .german: return "翻译成德语"
        case .spanish: return "翻译成西班牙语"
        }
    }
}

/// 一个可自定义的 AI 动作(提问/翻译/润色/总结/解释代码/自定义…)
struct AIAction: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String = "新动作"
    var icon: String = "wand.and.stars"
    var group: String = ""           // #10 分组标签(空=不分组)
    /// prompt 模板,{{text}} 替换为选中文字;{{lang}} 替换为目标语言指令(若为翻译类)
    var prompt: String = "{{text}}"
    var hotKey: HotKeyCombo? = nil
    var isTranslation: Bool = false
    var targetLanguage: TargetLanguage = .auto
    var replaceByDefault: Bool = false
    var isEnabled: Bool = true
    /// #2 Thinking/推理模式(Anthropic extended thinking 或 DeepSeek R1)
    var thinkingMode: Bool = false
    var thinkingBudget: Int = 8000   // Anthropic budget_tokens
    /// #1 动作专属供应商覆盖(nil = 使用全局激活的供应商)
    var providerID: String? = nil
    var modelOverride: String? = nil

    func render(text: String) -> String {
        var p = prompt.replacingOccurrences(of: "{{text}}", with: text)
        p = p.replacingOccurrences(of: "{{lang}}", with: targetLanguage.instruction)
        return p
    }

    static func defaults() -> [AIAction] {
        [
            AIAction(name: "提问", icon: "sparkles",
                     prompt: "请简洁、准确地回答关于以下内容的问题或解释它:\n\n{{text}}",
                     hotKey: HotKeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey))),
            AIAction(name: "翻译", icon: "character.bubble",
                     prompt: "请将下面的文字{{lang}}。只输出翻译结果,不要解释:\n\n{{text}}",
                     hotKey: HotKeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey)),
                     isTranslation: true, targetLanguage: .auto),
            AIAction(name: "润色", icon: "wand.and.stars",
                     prompt: "请润色下面的文字,使其更通顺、自然、专业,保持原意和原语言。只输出润色后的结果:\n\n{{text}}",
                     replaceByDefault: true),
            AIAction(name: "总结", icon: "list.bullet.rectangle",
                     prompt: "请用简洁的要点总结下面的内容,抓住关键信息:\n\n{{text}}"),
            AIAction(name: "解释代码", icon: "chevron.left.forwardslash.chevron.right",
                     prompt: "请解释下面这段代码的功能、关键逻辑和潜在问题,用简洁的中文:\n\n{{text}}")
        ]
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon, group, prompt, hotKey, isTranslation, targetLanguage
        case replaceByDefault, isEnabled, thinkingMode, thinkingBudget, providerID, modelOverride
    }
}
