import Foundation

struct ConversationExport {
    var actionName: String
    var sourceText: String
    var outputText: String
    var providerName: String
    var modelName: String
    var elapsed: TimeInterval
    var diagnostics: String
    var protectsContent: Bool = false
    var date: Date = Date()

    var markdown: String {
        let safeActionName = singleLine(actionName, fallback: "未命名动作", limit: 80)
        let modelText = [providerName, modelName]
            .map { singleLine($0, fallback: "", limit: 120) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        let sourceSection = protectsContent ? "因高风险隐私保护,未导出原文。" : sourceText
        let outputSection = protectsContent ? "因高风险隐私保护,未导出结果。" : outputText
        var sections = [
            "# \(safeActionName) - \(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short))",
            "## 原文\n\n\(sourceSection)",
            "## 结果\n\n\(outputSection)",
            "*模型: \(modelText.isEmpty ? "未记录" : modelText) | 耗时: \(String(format: "%.1f", elapsed))s*"
        ]
        if protectsContent {
            sections.append("## 隐私保护\n\n本次请求被标记为高隐私风险,对话导出已省略原文与结果正文。")
        }
        let trimmedDiagnostics = SensitiveTextSanitizer.sanitizedDiagnosticText(diagnostics)
        if !trimmedDiagnostics.isEmpty {
            let fence = codeFence(for: trimmedDiagnostics)
            sections.append("## 诊断\n\n\(fence)text\n\(trimmedDiagnostics)\n\(fence)")
        }
        return sections.joined(separator: "\n\n---\n\n")
    }

    private func singleLine(_ text: String, fallback: String, limit: Int) -> String {
        let cleaned = SensitiveTextSanitizer.sanitizedMessage(text, limit: limit)
        return cleaned.isEmpty ? fallback : cleaned
    }

    private func codeFence(for text: String) -> String {
        var fence = "```"
        while text.contains(fence) {
            fence += "`"
        }
        return fence
    }
}
