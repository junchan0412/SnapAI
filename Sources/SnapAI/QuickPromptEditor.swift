import SnapAILogic
import AppKit
import SwiftUI

// MARK: - 自适应无边框快捷提问编辑器

struct QuickPromptEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    var placeholder: String
    var minHeight: CGFloat = 56
    var maxHeight: CGFloat = 200
    var onSubmit: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(text: Binding<String>,
         measuredHeight: Binding<CGFloat> = .constant(56),
         placeholder: String,
         minHeight: CGFloat = 56,
         maxHeight: CGFloat = 200,
         onSubmit: @escaping () -> Void) {
        self._text = text
        self._measuredHeight = measuredHeight
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.onSubmit = onSubmit
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: minHeight))
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.setAccessibilityLabel("提问内容")
        textView.setAccessibilityHelp("回车发送，Shift 或 Option 加回车换行")
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 4

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.isEditable = isEnabled
        textView.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        if textView.string != text {
            textView.string = text
        }
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak textView, weak coordinator] in
            guard let textView, let coordinator else { return }
            coordinator.recalculateHeight(for: textView)
        }

        guard !context.coordinator.didAttemptFocus else { return }
        context.coordinator.didAttemptFocus = true
        DispatchQueue.main.async { [weak scrollView, weak textView] in
            guard let scrollView, let textView else { return }
            scrollView.window?.initialFirstResponder = textView
            scrollView.window?.makeFirstResponder(textView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QuickPromptEditor
        var didAttemptFocus = false

        init(_ parent: QuickPromptEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalculateHeight(for: textView)
        }

        func recalculateHeight(for textView: NSTextView) {
            guard let container = textView.textContainer,
                  let layout = textView.layoutManager else { return }
            layout.ensureLayout(for: container)
            let used = ceil(layout.usedRect(for: container).height + textView.textContainerInset.height * 2)
            let clamped = min(parent.maxHeight, max(parent.minHeight, used))
            if abs(parent.measuredHeight - clamped) > 0.5 {
                parent.measuredHeight = clamped
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            guard !textView.hasMarkedText() else { return false }
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            if flags.contains(.shift) || flags.contains(.option) {
                return false
            }
            parent.onSubmit()
            return true
        }
    }
}
