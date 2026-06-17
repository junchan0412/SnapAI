import Foundation
import Carbon.HIToolbox
import Combine

/// AI 协议类型
enum APIProtocol: String, Codable, CaseIterable, Identifiable {
    case openAI = "OpenAI 兼容"
    case anthropic = "Anthropic 原生"
    var id: String { rawValue }
}

/// 打字机动画速度
enum TypewriterSpeed: String, Codable, CaseIterable, Identifiable {
    case off = "关闭"
    case slow = "慢"
    case normal = "标准"
    case fast = "快"
    var id: String { rawValue }

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

/// 一个可配置的快捷键(键码 + 修饰键)
struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon 修饰键掩码 (cmdKey/optionKey/...)

    static let askDefault = HotKeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey))
    static let translateDefault = HotKeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey))

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

/// 全局设置,持久化到 UserDefaults
final class AppSettings: ObservableObject, Codable {
    static let shared = AppSettings.load()
    static let defaultAskPrompt = "请简洁、准确地回答关于以下内容的问题或解释它:\n\n{{text}}"
    static let oldDefaultTranslatePrompt = "请把下面的文字翻译成中文;如果它本身就是中文,则翻译成英文。只输出翻译结果,不要解释:\n\n{{text}}"
    static let defaultTranslatePrompt = "请将下面的文字在中文和英文之间互译:如果原文是中文,翻译成自然流畅的英文;如果原文是英文或其他语言,翻译成简体中文。只输出翻译结果,不要解释:\n\n{{text}}"
    static let defaultSystemPrompt = "你是一个简洁高效的助手,直接给出答案,避免冗余的客套话。"

    // AI 接入配置:多供应商
    @Published var providers: [AIProvider] = []
    @Published var activeProviderID: String = ""   // 当前激活的供应商 id
    @Published var activeModel: String = ""        // 当前激活的模型名
    @Published var temperature: Double = 0.3

    // 快捷键(旧:仅保留用于迁移与「快捷输入面板」)
    @Published var askHotKey: HotKeyCombo = .askDefault
    @Published var translateHotKey: HotKeyCombo = .translateDefault
    /// 快捷输入面板(不依赖选中文字)的全局快捷键
    @Published var quickPanelHotKey: HotKeyCombo = HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    // 自定义动作(提问/翻译/润色/总结/解释代码…)
    @Published var actions: [AIAction] = AIAction.defaults()

    // Prompt 模板,{{text}} 会被替换为选中文字(systemPrompt 仍全局生效)
    @Published var askPrompt: String = AppSettings.defaultAskPrompt
    @Published var translatePrompt: String = AppSettings.defaultTranslatePrompt
    @Published var systemPrompt: String = AppSettings.defaultSystemPrompt

    // 行为
    @Published var useAXFirst: Bool = true   // 优先用辅助功能取词
    @Published var showDockIcon: Bool = true // 在 Dock 显示图标(可点击打开设置)
    @Published var typewriterSpeed: TypewriterSpeed = .normal // 打字机动画速度

    // 历史 / 引导 / 窗口尺寸
    @Published var history: [HistoryEntry] = []
    @Published var historyLimit: Int = 50
    @Published var onboardingDone: Bool = false
    @Published var panelWidth: Double = 420
    @Published var panelHeight: Double = 360

    // MARK: - 当前激活配置(兼容旧的扁平访问方式,供 AIClient / ModelLoader 使用)

    /// 当前激活的供应商(找不到时回退到第一个)
    var activeProvider: AIProvider? {
        providers.first(where: { $0.id == activeProviderID }) ?? providers.first
    }

    var apiProtocol: APIProtocol { activeProvider?.apiProtocol ?? .openAI }
    var baseURL: String { activeProvider?.baseURL ?? "" }
    var apiKey: String { activeProvider?.apiKey ?? "" }
    var model: String { activeModel }

    /// 选中某个供应商的某个模型为当前激活
    func activate(providerID: String, model: String) {
        activeProviderID = providerID
        activeModel = model
        save()
    }

    /// 确保激活态有效:激活的供应商/模型若失效,自动落到第一个可用的启用项
    func normalizeActive() {
        // 供应商:必须存在且启用
        if !providers.contains(where: { $0.id == activeProviderID && $0.isEnabled }) {
            if let first = providers.first(where: { $0.isEnabled }) ?? providers.first {
                activeProviderID = first.id
            }
        }
        // 模型:必须在激活供应商的启用模型里
        if let p = activeProvider {
            let enabled = p.enabledModelNames
            if !enabled.contains(activeModel) {
                activeModel = enabled.first ?? p.models.first?.name ?? ""
            }
        } else {
            activeModel = ""
        }
    }

    /// 所有「启用供应商 → 启用模型」的扁平条目,用于菜单栏快速切换
    var switchableEntries: [(provider: AIProvider, model: String)] {
        var result: [(AIProvider, String)] = []
        for p in providers where p.isEnabled {
            for m in p.enabledModelNames {
                result.append((p, m))
            }
        }
        return result
    }

    /// 启用的动作(用于菜单/快捷键注册)
    var enabledActions: [AIAction] { actions.filter { $0.isEnabled } }

    // MARK: - 历史记录

    /// 追加一条历史并裁剪到上限
    func addHistory(action: String, source: String, output: String,
                    provider: String, model: String) {
        guard historyLimit > 0 else { return }
        let entry = HistoryEntry(actionName: action, source: source, output: output,
                                 provider: provider, model: model)
        history.insert(entry, at: 0)
        if history.count > historyLimit {
            history = Array(history.prefix(historyLimit))
        }
        save()
    }

    func clearHistory() {
        history.removeAll()
        save()
    }

    enum CodingKeys: String, CodingKey {
        // 新:多供应商
        case providers, activeProviderID, activeModel
        case temperature
        case askHotKey, translateHotKey, quickPanelHotKey
        case actions
        case askPrompt, translatePrompt, systemPrompt, useAXFirst, showDockIcon
        case typewriterSpeed
        case history, historyLimit, onboardingDone, panelWidth, panelHeight
        // 旧:单配置(仅用于迁移,不再写出)
        case apiProtocol, baseURL, apiKey, model
    }

    init() {
        providers = [AIProvider.preset(.openAI)]
        if let first = providers.first {
            activeProviderID = first.id
            activeModel = first.models.first?.name ?? ""
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        temperature = (try? c.decode(Double.self, forKey: .temperature)) ?? 0.3
        askHotKey = (try? c.decode(HotKeyCombo.self, forKey: .askHotKey)) ?? .askDefault
        translateHotKey = (try? c.decode(HotKeyCombo.self, forKey: .translateHotKey)) ?? .translateDefault
        askPrompt = (try? c.decode(String.self, forKey: .askPrompt)) ?? askPrompt
        translatePrompt = (try? c.decode(String.self, forKey: .translatePrompt)) ?? translatePrompt
        if translatePrompt == Self.oldDefaultTranslatePrompt {
            translatePrompt = Self.defaultTranslatePrompt
        }
        systemPrompt = (try? c.decode(String.self, forKey: .systemPrompt)) ?? systemPrompt
        useAXFirst = (try? c.decode(Bool.self, forKey: .useAXFirst)) ?? true
        showDockIcon = (try? c.decode(Bool.self, forKey: .showDockIcon)) ?? true
        typewriterSpeed = (try? c.decode(TypewriterSpeed.self, forKey: .typewriterSpeed)) ?? .normal

        quickPanelHotKey = (try? c.decode(HotKeyCombo.self, forKey: .quickPanelHotKey))
            ?? HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

        // 动作:有则用,无则用默认 5 个;并把旧的 ask/translate 快捷键迁移到对应动作
        if let acts = try? c.decode([AIAction].self, forKey: .actions), !acts.isEmpty {
            actions = acts
        } else {
            var defs = AIAction.defaults()
            if let ah = try? c.decode(HotKeyCombo.self, forKey: .askHotKey), defs.indices.contains(0) {
                defs[0].hotKey = ah
            }
            if let th = try? c.decode(HotKeyCombo.self, forKey: .translateHotKey), defs.indices.contains(1) {
                defs[1].hotKey = th
            }
            // 旧的自定义提问/翻译模板若被改过,沿用到对应动作
            if let ap = try? c.decode(String.self, forKey: .askPrompt), ap != Self.defaultAskPrompt, defs.indices.contains(0) {
                defs[0].prompt = ap
            }
            actions = defs
        }

        history = (try? c.decode([HistoryEntry].self, forKey: .history)) ?? []
        historyLimit = (try? c.decode(Int.self, forKey: .historyLimit)) ?? 50
        // 已有存档的老用户视为已完成引导(缺该键时默认 true);全新安装走 init() 默认 false
        onboardingDone = (try? c.decode(Bool.self, forKey: .onboardingDone)) ?? true
        panelWidth = (try? c.decode(Double.self, forKey: .panelWidth)) ?? 420
        panelHeight = (try? c.decode(Double.self, forKey: .panelHeight)) ?? 360

        if let list = try? c.decode([AIProvider].self, forKey: .providers), !list.isEmpty {
            // 新格式
            providers = list
            activeProviderID = (try? c.decode(String.self, forKey: .activeProviderID)) ?? list.first!.id
            activeModel = (try? c.decode(String.self, forKey: .activeModel)) ?? ""
        } else {
            // 旧格式迁移:把单一配置包装成一个供应商
            let proto = (try? c.decode(APIProtocol.self, forKey: .apiProtocol)) ?? .openAI
            let url = (try? c.decode(String.self, forKey: .baseURL)) ?? "https://api.openai.com/v1"
            let key = (try? c.decode(String.self, forKey: .apiKey)) ?? ""
            let mdl = (try? c.decode(String.self, forKey: .model)) ?? "gpt-4o-mini"
            var p = AIProvider(name: "我的配置", apiProtocol: proto, baseURL: url, apiKey: key)
            if !mdl.isEmpty { p.models = [AIModelEntry(name: mdl)] }
            providers = [p]
            activeProviderID = p.id
            activeModel = mdl
        }
        normalizeActive()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(providers, forKey: .providers)
        try c.encode(activeProviderID, forKey: .activeProviderID)
        try c.encode(activeModel, forKey: .activeModel)
        try c.encode(temperature, forKey: .temperature)
        try c.encode(askHotKey, forKey: .askHotKey)
        try c.encode(translateHotKey, forKey: .translateHotKey)
        try c.encode(quickPanelHotKey, forKey: .quickPanelHotKey)
        try c.encode(actions, forKey: .actions)
        try c.encode(askPrompt, forKey: .askPrompt)
        try c.encode(translatePrompt, forKey: .translatePrompt)
        try c.encode(systemPrompt, forKey: .systemPrompt)
        try c.encode(useAXFirst, forKey: .useAXFirst)
        try c.encode(showDockIcon, forKey: .showDockIcon)
        try c.encode(typewriterSpeed, forKey: .typewriterSpeed)
        try c.encode(history, forKey: .history)
        try c.encode(historyLimit, forKey: .historyLimit)
        try c.encode(onboardingDone, forKey: .onboardingDone)
        try c.encode(panelWidth, forKey: .panelWidth)
        try c.encode(panelHeight, forKey: .panelHeight)
    }

    private static let storeKey = "SnapAI.settings.v1"

    static func load() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            let hadPlaintext = String(data: data, encoding: .utf8)?.contains("\"apiKey\"") ?? false
            s.loadKeysFromKeychain()
            // 旧版本可能把明文 Key 存在 JSON 里;迁移后立即重写一次以彻底清除明文
            if hadPlaintext { s.save() }
            return s
        }
        return AppSettings()
    }

    /// 已写入 Keychain 的 Key 快照,避免每次 save() 都重复写(打字时 commit 很频繁)
    private var keychainCache: [String: String] = [:]

    /// 从 Keychain 回填各供应商的 apiKey(decode 后它们都是空字符串)
    private func loadKeysFromKeychain() {
        for i in providers.indices {
            // 迁移分支可能已在内存里带了明文 key(来自旧 JSON),优先保留并落 Keychain
            if providers[i].apiKey.isEmpty {
                providers[i].apiKey = Keychain.apiKey(for: providers[i].id)
            } else {
                Keychain.setAPIKey(providers[i].apiKey, for: providers[i].id)
            }
            keychainCache[providers[i].id] = providers[i].apiKey
        }
    }

    func save() {
        // 仅当 Key 发生变化时才写 Keychain(避免打字时频繁写入)
        for p in providers where keychainCache[p.id] != p.apiKey {
            Keychain.setAPIKey(p.apiKey, for: p.id)
            keychainCache[p.id] = p.apiKey
        }
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
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
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋"
        ]
        return map[Int(keyCode)] ?? "Key\(keyCode)"
    }
}
