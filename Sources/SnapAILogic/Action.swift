import Foundation
import Carbon.HIToolbox

/// 翻译/输出目标语言
public enum TargetLanguage: String, Codable, CaseIterable, Identifiable {
    case auto = "自动(中英互译)"
    case chinese = "简体中文"
    case english = "英语"
    case japanese = "日语"
    case korean = "韩语"
    case french = "法语"
    case german = "德语"
    case spanish = "西班牙语"
    public var id: String { rawValue }

    /// 注入 prompt 的指令片段
    package var instruction: String {
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
package struct AIAction: Codable, Identifiable, Equatable {
    package static let askName = "提问"
    package static let translateName = "翻译"
    package static let polishName = "润色"
    package static let summarizeName = "总结"
    package static let explainCodeName = "解释代码"
    package static let defaultActionNames = [
        askName,
        translateName,
        polishName,
        summarizeName,
        explainCodeName
    ]
    package static let defaultHotKeysByName: [String: HotKeyCombo] = [
        askName: .askDefault,
        translateName: .translateDefault,
        polishName: .polishDefault,
        summarizeName: .summarizeDefault,
        explainCodeName: .explainCodeDefault
    ]
    package static let defaultThinkingBudget = 8_000
    package static let thinkingBudgetRange = 1_024...64_000
    package static let maxNameLength = 80
    package static let maxIconLength = 80
    package static let maxGroupLength = 80
    package static let maxPromptLength = 20_000

    package var id: String
    package var name: String
    package var icon: String
    package var group: String           // #10 分组标签(空=不分组)
    /// prompt 模板,{{text}} 替换为选中文字;{{lang}} 替换为目标语言指令(若为翻译类)
    package var prompt: String
    package var hotKey: HotKeyCombo?
    package var isTranslation: Bool
    package var targetLanguage: TargetLanguage
    package var replaceByDefault: Bool
    package var isEnabled: Bool
    /// #2 Thinking/推理模式(Anthropic extended thinking 或 DeepSeek R1)
    package var thinkingMode: Bool
    package var thinkingBudget: Int   // Anthropic budget_tokens
    /// #1 动作专属供应商覆盖(nil = 使用全局激活的供应商)
    package var providerID: String?
    package var modelOverride: String?
    /// 是否把该动作的结果写入历史。隐私敏感动作可以关闭。
    package var saveHistory: Bool

    package func render(text: String) -> String {
        var p = prompt.replacingOccurrences(of: "{{text}}", with: text)
        p = p.replacingOccurrences(of: "{{lang}}", with: targetLanguage.instruction)
        return p
    }

    package static func sanitizedThinkingBudget(_ value: Int) -> Int {
        min(max(value, thinkingBudgetRange.lowerBound), thinkingBudgetRange.upperBound)
    }

    package static func defaults() -> [AIAction] {
        [
            AIAction(name: askName, icon: "sparkles",
                     prompt: "请简洁、准确地回答关于以下内容的问题或解释它:\n\n{{text}}",
                     hotKey: defaultHotKeysByName[askName]),
            AIAction(name: translateName, icon: "character.bubble",
                     prompt: "请将下面的文字{{lang}}。只输出翻译结果,不要解释:\n\n{{text}}",
                     hotKey: defaultHotKeysByName[translateName],
                     isTranslation: true, targetLanguage: .auto),
            AIAction(name: polishName, icon: "wand.and.stars",
                     prompt: "请润色下面的文字,使其更通顺、自然、专业,保持原意和原语言。只输出润色后的结果:\n\n{{text}}",
                     hotKey: defaultHotKeysByName[polishName],
                     replaceByDefault: true),
            AIAction(name: summarizeName, icon: "list.bullet.rectangle",
                     prompt: "请用简洁的要点总结下面的内容,抓住关键信息:\n\n{{text}}",
                     hotKey: defaultHotKeysByName[summarizeName]),
            AIAction(name: explainCodeName, icon: "chevron.left.forwardslash.chevron.right",
                     prompt: "请解释下面这段代码的功能、关键逻辑和潜在问题,用简洁的中文:\n\n{{text}}",
                     hotKey: defaultHotKeysByName[explainCodeName])
        ]
    }

    package enum CodingKeys: String, CodingKey {
        case id, name, icon, group, prompt, hotKey, isTranslation, targetLanguage
        case replaceByDefault, isEnabled, thinkingMode, thinkingBudget, providerID, modelOverride
        case saveHistory
    }

    package init(id: String = UUID().uuidString,
                 name: String = "新动作",
                 icon: String = "wand.and.stars",
                 group: String = "",
                 prompt: String = "{{text}}",
                 hotKey: HotKeyCombo? = nil,
                 isTranslation: Bool = false,
                 targetLanguage: TargetLanguage = .auto,
                 replaceByDefault: Bool = false,
                 isEnabled: Bool = true,
                 thinkingMode: Bool = false,
                 thinkingBudget: Int = AIAction.defaultThinkingBudget,
                 providerID: String? = nil,
                 modelOverride: String? = nil,
                 saveHistory: Bool = true) {
        self.id = id
        self.name = name
        self.icon = icon
        self.group = group
        self.prompt = prompt
        self.hotKey = hotKey
        self.isTranslation = isTranslation
        self.targetLanguage = targetLanguage
        self.replaceByDefault = replaceByDefault
        self.isEnabled = isEnabled
        self.thinkingMode = thinkingMode
        self.thinkingBudget = thinkingBudget
        self.providerID = providerID
        self.modelOverride = modelOverride
        self.saveHistory = saveHistory
    }
}

extension AIAction {
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "新动作"
        icon = (try? c.decode(String.self, forKey: .icon)) ?? "wand.and.stars"
        group = (try? c.decode(String.self, forKey: .group)) ?? ""
        prompt = (try? c.decode(String.self, forKey: .prompt)) ?? "{{text}}"
        hotKey = try? c.decode(HotKeyCombo.self, forKey: .hotKey)
        isTranslation = (try? c.decode(Bool.self, forKey: .isTranslation)) ?? false
        targetLanguage = (try? c.decode(TargetLanguage.self, forKey: .targetLanguage)) ?? .auto
        replaceByDefault = (try? c.decode(Bool.self, forKey: .replaceByDefault)) ?? false
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
        thinkingMode = (try? c.decode(Bool.self, forKey: .thinkingMode)) ?? false
        thinkingBudget = Self.sanitizedThinkingBudget((try? c.decode(Int.self, forKey: .thinkingBudget)) ?? Self.defaultThinkingBudget)
        providerID = try? c.decode(String.self, forKey: .providerID)
        modelOverride = try? c.decode(String.self, forKey: .modelOverride)
        saveHistory = (try? c.decode(Bool.self, forKey: .saveHistory)) ?? true
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(icon, forKey: .icon)
        try c.encode(group, forKey: .group)
        try c.encode(prompt, forKey: .prompt)
        try c.encodeIfPresent(hotKey, forKey: .hotKey)
        try c.encode(isTranslation, forKey: .isTranslation)
        try c.encode(targetLanguage, forKey: .targetLanguage)
        try c.encode(replaceByDefault, forKey: .replaceByDefault)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(thinkingMode, forKey: .thinkingMode)
        try c.encode(thinkingBudget, forKey: .thinkingBudget)
        try c.encodeIfPresent(providerID, forKey: .providerID)
        try c.encodeIfPresent(modelOverride, forKey: .modelOverride)
        try c.encode(saveHistory, forKey: .saveHistory)
    }
}
