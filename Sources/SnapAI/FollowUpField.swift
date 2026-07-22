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

    private var placeholderText: String {
        historyAvailable ? "追问…  (↑ 浏览历史)" : FollowUpInputBehavior.placeholder
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            FollowUpTextView(text: $text,
                             onSubmit: onSubmit,
                             onHistoryUp: onHistoryUp,
                             onHistoryDown: onHistoryDown,
                             shouldHandleHistoryNavigation: shouldHandleHistoryNavigation)
                .frame(minHeight: CGFloat(FollowUpInputBehavior.minHeight),
                       maxHeight: CGFloat(FollowUpInputBehavior.maxHeight))

            if text.isEmpty {
                Text(placeholderText)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        .help(FollowUpInputBehavior.helpText)
        .accessibilityLabel(FollowUpInputBehavior.accessibilityLabel)
        .accessibilityHint(FollowUpInputBehavior.helpText)
    }
}

private struct FollowUpTextView: NSViewRepresentable {
    @Binding var text: String
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
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 7, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
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
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FollowUpTextView
        init(_ parent: FollowUpTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
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
