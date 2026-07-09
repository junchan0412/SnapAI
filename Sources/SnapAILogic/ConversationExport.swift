import Foundation

public struct ConversationExport {
    public var actionName: String
    public var sourceText: String
    public var outputText: String
    public var providerName: String
    public var modelName: String
    public var elapsed: TimeInterval
    public var diagnostics: String
    public var protectsContent: Bool
    public var date: Date

    public init(actionName: String,
                sourceText: String,
                outputText: String,
                providerName: String,
                modelName: String,
                elapsed: TimeInterval,
                diagnostics: String,
                protectsContent: Bool = false,
                date: Date = Date()) {
        self.actionName = actionName
        self.sourceText = sourceText
        self.outputText = outputText
        self.providerName = providerName
        self.modelName = modelName
        self.elapsed = elapsed
        self.diagnostics = diagnostics
        self.protectsContent = protectsContent
        self.date = date
    }

    public var markdown: String {
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
