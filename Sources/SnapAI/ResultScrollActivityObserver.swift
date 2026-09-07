import SnapAILogic
import AppKit
import SwiftUI

struct ResultScrollActivityObserver: NSViewRepresentable {
    var onUserScroll: () -> Void

    func makeNSView(context: Context) -> ScrollActivityView {
        let view = ScrollActivityView()
        view.onUserScroll = onUserScroll
        return view
    }

    func updateNSView(_ view: ScrollActivityView, context: Context) {
        view.onUserScroll = onUserScroll
    }

    static func dismantleNSView(_ view: ScrollActivityView, coordinator: ()) {
        view.disconnect()
    }

    final class ScrollActivityView: NSView {
        var onUserScroll: () -> Void = {}
        private var observer: NSObjectProtocol?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            disconnect()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil,
                      let scrollView = self.enclosingScrollView else { return }
                self.disconnect()
                self.observer = NotificationCenter.default.addObserver(
                    forName: NSScrollView.willStartLiveScrollNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self] _ in
                    self?.onUserScroll()
                }
            }
        }

        func disconnect() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
