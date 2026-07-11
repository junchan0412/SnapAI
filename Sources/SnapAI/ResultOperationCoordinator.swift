import AppKit
import Combine
import SnapAILogic
import UniformTypeIdentifiers

@MainActor
final class ResultOperationCoordinator: ObservableObject {
    @Published private(set) var feedback: ResultOperationFeedback?
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func copy(text: String,
              successMessage: String,
              emptyMessage: String) {
        guard !text.isEmpty else {
            feedback = .warning(emptyMessage)
            return
        }
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            feedback = .warning("复制失败，请检查剪贴板权限后重试。")
            return
        }
        feedback = .success(successMessage)
    }

    func replace(original: String,
                 replacement: String,
                 handler: ((String, String) -> Void)?) {
        ResultWriteBackCoordinator.replace(original: original,
                                           replacement: replacement,
                                           handler: handler)
    }

    func append(text: String, handler: ((String) -> Void)?) {
        ResultWriteBackCoordinator.append(text: text, handler: handler)
    }

    func export(markdown: String,
                actionName: String,
                date: Date = Date()) {
        guard !markdown.isEmpty else {
            feedback = .warning("当前没有可导出的对话内容。")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ResultExportFilename.suggested(
            actionName: actionName,
            timestamp: Int(date.timeIntervalSince1970)
        )
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .text]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            feedback = .success("已导出 \(url.lastPathComponent)")
        } catch {
            let reason = SensitiveTextSanitizer.sanitizedMessage(error.localizedDescription,
                                                                 limit: 120)
            feedback = .warning(reason.isEmpty ? "导出失败，请检查保存位置后重试。" : "导出失败：\(reason)")
        }
    }

    func dismissFeedback(id: UUID) {
        guard feedback?.id == id else { return }
        feedback = nil
    }

    func clearFeedback() {
        feedback = nil
    }
}
