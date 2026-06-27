import Foundation

/// 一条历史记录(一次问答)
struct HistoryEntry: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var date: Date = Date()
    var actionName: String       // 动作名,如「翻译」
    var source: String           // 原始输入文字
    var output: String           // AI 输出
    var provider: String         // 供应商名
    var model: String            // 模型名
    var isFavorite: Bool = false

    /// 列表里显示的简短预览
    var preview: String {
        let s = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count > 40 ? String(s.prefix(40)) + "…" : s
    }

    var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    enum CodingKeys: String, CodingKey {
        case id, date, actionName, source, output, provider, model, isFavorite
    }
}

extension HistoryEntry {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        date = (try? c.decode(Date.self, forKey: .date)) ?? Date()
        actionName = (try? c.decode(String.self, forKey: .actionName)) ?? ""
        source = (try? c.decode(String.self, forKey: .source)) ?? ""
        output = (try? c.decode(String.self, forKey: .output)) ?? ""
        provider = (try? c.decode(String.self, forKey: .provider)) ?? ""
        model = (try? c.decode(String.self, forKey: .model)) ?? ""
        isFavorite = (try? c.decode(Bool.self, forKey: .isFavorite)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(actionName, forKey: .actionName)
        try c.encode(source, forKey: .source)
        try c.encode(output, forKey: .output)
        try c.encode(provider, forKey: .provider)
        try c.encode(model, forKey: .model)
        try c.encode(isFavorite, forKey: .isFavorite)
    }
}
