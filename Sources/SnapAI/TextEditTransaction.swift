import AppKit

@MainActor
struct TextEditTransaction {
    var targetApp: NSRunningApplication?
    var focusDelay: TimeInterval = 0.18
    var restoreDelay: TimeInterval = 0.35

    func replace(with text: String) {
        paste(text)
    }

    func append(_ text: String) {
        paste("\n" + text) {
            TextCapture.sendRightArrow()
        }
    }

    private func paste(_ text: String, beforePaste: (() -> Void)? = nil) {
        let pasteboard = NSPasteboard.general
        let previousItems = TextCapture.snapshotPasteboard(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        targetApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay) {
            beforePaste?()
            DispatchQueue.main.asyncAfter(deadline: .now() + (beforePaste == nil ? 0 : 0.05)) {
                TextCapture.sendCmdV()
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                    TextCapture.restorePasteboard(pasteboard, items: previousItems)
                }
            }
        }
    }
}
