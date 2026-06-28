import AppKit

@MainActor
struct TextEditTransaction {
    var targetApp: NSRunningApplication?
    var selectionSnapshot: TextSelectionSnapshot?
    var focusDelay: TimeInterval = 0.18
    var restoreDelay: TimeInterval = 0.35

    func replace(original: String, with text: String) {
        paste(text) {
            guard TextCapture.selectedTextViaAX()?.isEmpty != false else { return 0.03 }
            if selectionSnapshot?.restoreSelection() == true {
                return 0.08
            }
            TextCapture.sendShiftLeftArrow(repeat: original.count)
            return Self.selectionDelay(forCharacterCount: original.count)
        }
    }

    func append(_ text: String) {
        paste("\n" + text) {
            TextCapture.sendRightArrow()
            return 0.05
        }
    }

    nonisolated static func selectionDelay(forCharacterCount count: Int) -> TimeInterval {
        guard count > 0 else { return 0.03 }
        return min(0.75, 0.05 + Double(count) * 0.0015)
    }

    private func paste(_ text: String, beforePaste: (() -> TimeInterval)? = nil) {
        let pasteboard = NSPasteboard.general
        let previousItems = TextCapture.snapshotPasteboard(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        targetApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay) {
            let pasteDelay = beforePaste?() ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
                TextCapture.sendCmdV()
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                    TextCapture.restorePasteboard(pasteboard, items: previousItems)
                    TextCapture.clearRecentSelectionSnapshot()
                }
            }
        }
    }
}
