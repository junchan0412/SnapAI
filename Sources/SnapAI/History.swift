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
}
