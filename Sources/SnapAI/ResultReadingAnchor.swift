import AppKit
import SwiftUI
import SnapAILogic

@MainActor
final class ResultReadingAnchor: ObservableObject {
    fileprivate weak var view: NSView?
    private var position: MarkdownReadingPosition?

    func capture() {
        cancel()
        guard let view, let scroll = view.enclosingScrollView,
              let document = scroll.documentView else { return }
        let frame = view.convert(view.bounds, to: document)
        let visible = document.convert(scroll.contentView.bounds, from: scroll.contentView)
        let contentTop = document.isFlipped ? frame.minY : document.bounds.maxY - frame.maxY
        let viewportTop = document.isFlipped ? visible.minY : document.bounds.maxY - visible.maxY
        position = MarkdownReadingPosition(viewportTop: viewportTop, contentTop: contentTop,
                                           contentHeight: frame.height)
    }

    func restore() {
        guard position != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let position = self.position,
                  let view = self.view, let scroll = view.enclosingScrollView,
                  let document = scroll.documentView else { return }
            defer { self.cancel() }
            document.layoutSubtreeIfNeeded()
            let frame = view.convert(view.bounds, to: document)
            let visible = document.convert(scroll.contentView.bounds, from: scroll.contentView)
            let contentTop = document.isFlipped ? frame.minY : document.bounds.maxY - frame.maxY
            let restoredTop = position.restoredTop(contentTop: contentTop, contentHeight: frame.height,
                                                  maximumScrollTop: max(0, document.bounds.height - visible.height))
            let targetY = document.isFlipped ? restoredTop : document.bounds.maxY - visible.height - restoredTop
            var target = scroll.contentView.bounds.origin
            target.y += targetY - visible.minY
            scroll.contentView.scroll(to: target)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    func cancel() {
        position = nil
    }
}

struct ResultReadingAnchorObserver: NSViewRepresentable {
    let anchor: ResultReadingAnchor
    var isStreaming: Bool
    var followsOutput: Bool

    func makeNSView(context: Context) -> NSView {
        let view = AnchorView()
        anchor.view = view
        context.coordinator.wasStreaming = isStreaming
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
        if followsOutput {
            anchor.cancel()
        } else if context.coordinator.wasStreaming && !isStreaming {
            anchor.capture()
        }
        context.coordinator.wasStreaming = isStreaming
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var wasStreaming = false
    }

    private final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
