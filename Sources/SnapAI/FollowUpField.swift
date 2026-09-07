import SwiftUI
import AppKit
import SnapAILogic

// MARK: - 追问框(#5 支持↑/↓浏览历史)

struct FollowUpField: View {
    @Binding var text: String
    var onSubmit: () -> Void
    var onHistoryUp: () -> Void
    var onHistoryDown: () -> Void
    var historyAvailable: Bool = false
    var shouldHandleHistoryNavigation: (String, FollowUpHistoryNavigationDirection) -> Bool
    @State private var editorHeight: CGFloat = 42
    @State private var isFocused = false

    private var placeholderText: String {
        historyAvailable ? "继续追问…  ↑ 浏览历史" : "继续追问，或补充一个要求…"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            FollowUpTextView(text: $text,
                             height: $editorHeight,
                             isFocused: $isFocused,
                             onSubmit: onSubmit,
                             onHistoryUp: onHistoryUp,
                             onHistoryDown: onHistoryDown,
                             shouldHandleHistoryNavigation: shouldHandleHistoryNavigation)
                .frame(height: editorHeight)

            if text.isEmpty {
                Text(placeholderText)
                    .font(SnapAIUI.Typography.bodyText)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .allowsHitTesting(false)
            }
        }
        .background(SnapAIUI.Surface.field)
        .clipShape(RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous)
                .stroke(isFocused ? SnapAIUI.Surface.focus : SnapAIUI.Surface.divider,
                        lineWidth: isFocused ? 2 : 1)
        }
        .help(FollowUpInputBehavior.helpText)
        .accessibilityLabel(FollowUpInputBehavior.accessibilityLabel)
        .accessibilityHint(FollowUpInputBehavior.helpText)
    }
}

private struct FollowUpTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var isFocused: Bool
    var onSubmit: () -> Void
    var onHistoryUp: () -> Void
    var onHistoryDown: () -> Void
    var shouldHandleHistoryNavigation: (String, FollowUpHistoryNavigationDirection) -> Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.toolTip = FollowUpInputBehavior.helpText
        scrollView.setAccessibilityLabel(FollowUpInputBehavior.accessibilityLabel)
        scrollView.setAccessibilityHelp(FollowUpInputBehavior.helpText)

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 9, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.string = text
        textView.toolTip = FollowUpInputBehavior.helpText
        textView.setAccessibilityLabel(FollowUpInputBehavior.accessibilityLabel)
        textView.setAccessibilityHelp(FollowUpInputBehavior.helpText)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEnabled
        textView.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        textView.toolTip = FollowUpInputBehavior.helpText
        textView.setAccessibilityLabel(FollowUpInputBehavior.accessibilityLabel)
        textView.setAccessibilityHelp(FollowUpInputBehavior.helpText)
        nsView.toolTip = FollowUpInputBehavior.helpText
        nsView.setAccessibilityLabel(FollowUpInputBehavior.accessibilityLabel)
        nsView.setAccessibilityHelp(FollowUpInputBehavior.helpText)
        context.coordinator.parent = self
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak textView, weak coordinator] in
            guard let textView, let coordinator else { return }
            coordinator.updateHeight(for: textView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FollowUpTextView
        init(_ parent: FollowUpTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateHeight(for: textView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func updateHeight(for textView: NSTextView) {
            guard let container = textView.textContainer,
                  let layout = textView.layoutManager else { return }
            layout.ensureLayout(for: container)
            let measured = ceil(layout.usedRect(for: container).height + textView.textContainerInset.height * 2)
            let nextHeight = min(CGFloat(FollowUpInputBehavior.maxHeight), max(42, measured))
            if abs(parent.height - nextHeight) > 0.5 {
                parent.height = nextHeight
            }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            if selector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                let behavior = FollowUpInputBehavior.returnKeyBehavior(
                    shift: flags.contains(.shift),
                    option: flags.contains(.option)
                )
                if behavior == .insertNewline {
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                } else {
                    parent.onSubmit()
                }
                return true
            }
            if selector == #selector(NSResponder.moveUp(_:)) {
                if parent.shouldHandleHistoryNavigation(textView.string, .up) {
                    parent.onHistoryUp()
                    return true
                }
                return false
            }
            if selector == #selector(NSResponder.moveDown(_:)) {
                if parent.shouldHandleHistoryNavigation(textView.string, .down) {
                    parent.onHistoryDown()
                    return true
                }
                return false
            }
            return false
        }
    }
}
