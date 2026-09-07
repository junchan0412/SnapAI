import SnapAILogic
import AppKit
import SwiftUI

// MARK: - 多行快捷提问输入框

struct QuickPromptEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> PromptEditorContainer {
        let container = PromptEditorContainer()
        let scrollView = container.scrollView
        let textView = container.textView

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        textView.placeholderString = placeholder
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 16)
        textView.setAccessibilityLabel("提问内容")
        textView.setAccessibilityHelp("回车发送，Shift 或 Option 加回车换行")
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        scrollView.documentView = textView
        container.install(scrollView)
        return container
    }

    func updateNSView(_ container: PromptEditorContainer, context: Context) {
        let scrollView = container.scrollView
        let textView = container.textView
        context.coordinator.parent = self
        textView.placeholderString = placeholder
        textView.isEditable = isEnabled
        textView.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width,
                                                       height: CGFloat.greatestFiniteMagnitude)

        guard !context.coordinator.didAttemptFocus else { return }
        context.coordinator.didAttemptFocus = true
        DispatchQueue.main.async { [weak container, weak textView] in
            guard let container, let textView else { return }
            container.window?.initialFirstResponder = textView
            container.window?.makeFirstResponder(textView)
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
            textView.needsDisplay = true
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            (textView.enclosingScrollView?.superview as? PromptEditorContainer)?.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            (textView.enclosingScrollView?.superview as? PromptEditorContainer)?.isFocused = false
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

final class PromptEditorContainer: NSView {
    let scrollView = NSScrollView()
    let textView = PlaceholderTextView()
    var isFocused = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    func install(_ scrollView: NSScrollView) {
        guard scrollView.superview == nil else { return }
        addSubview(scrollView)
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds.insetBy(dx: 3, dy: 3)
        let contentSize = scrollView.contentSize
        textView.frame = NSRect(x: 0,
                                y: 0,
                                width: contentSize.width,
                                height: max(contentSize.height, textView.frame.height))
        textView.textContainer?.containerSize = NSSize(width: contentSize.width,
                                                       height: CGFloat.greatestFiniteMagnitude)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let borderWidth: CGFloat = isFocused ? 2 : 1
        let rect = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        NSColor.textBackgroundColor.setFill()
        path.fill()
        (isFocused ? NSColor.controlAccentColor.withAlphaComponent(0.65) : NSColor.separatorColor.withAlphaComponent(0.4)).setStroke()
        path.lineWidth = borderWidth
        path.stroke()
    }
}

final class PlaceholderTextView: NSTextView {
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }

        let rect = NSRect(
            x: textContainerInset.width + 4,
            y: textContainerInset.height,
            width: bounds.width - textContainerInset.width * 2 - 8,
            height: bounds.height - textContainerInset.height * 2
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        (placeholderString as NSString).draw(in: rect, withAttributes: attributes)
    }
}
