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
    static let askName = "提问"
    static let translateName = "翻译"
    static let polishName = "润色"
    static let summarizeName = "总结"
    static let explainCodeName = "解释代码"
    static let defaultActionNames = [
        askName,
        translateName,
        polishName,
        summarizeName,
        explainCodeName
    ]
    static let defaultHotKeysByName: [String: HotKeyCombo] = [
        askName: .askDefault,
        translateName: .translateDefault,
        polishName: .polishDefault,
        summarizeName: .summarizeDefault,
        explainCodeName: .explainCodeDefault
    ]
    static let defaultThinkingBudget = 8_000
    static let thinkingBudgetRange = 1_024...64_000
    static let maxNameLength = 80
    static let maxIconLength = 80
    static let maxGroupLength = 80
    static let maxPromptLength = 20_000

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
    var thinkingBudget: Int = Self.defaultThinkingBudget   // Anthropic budget_tokens
    /// #1 动作专属供应商覆盖(nil = 使用全局激活的供应商)
    var providerID: String? = nil
    var modelOverride: String? = nil
    /// 是否把该动作的结果写入历史。隐私敏感动作可以关闭。
    var saveHistory: Bool = true

    func render(text: String) -> String {
        var p = prompt.replacingOccurrences(of: "{{text}}", with: text)
        p = p.replacingOccurrences(of: "{{lang}}", with: targetLanguage.instruction)
        return p
    }

    static func sanitizedThinkingBudget(_ value: Int) -> Int {
        min(max(value, thinkingBudgetRange.lowerBound), thinkingBudgetRange.upperBound)
    }

    static func defaults() -> [AIAction] {
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

    enum CodingKeys: String, CodingKey {
        case id, name, icon, group, prompt, hotKey, isTranslation, targetLanguage
        case replaceByDefault, isEnabled, thinkingMode, thinkingBudget, providerID, modelOverride
        case saveHistory
    }
}

extension AIAction {
    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
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
