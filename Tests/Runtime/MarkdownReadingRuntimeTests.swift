import AppKit
import SwiftUI

@MainActor
private final class MarkdownReadingRecorder {
    weak var contentView: NSView?
    var readyCount = 0
    var scrollToEndpoint: ((Bool) -> Void)?

    var scrollView: NSScrollView? { contentView?.enclosingScrollView }

    var visibleContent: NSRect? {
        guard let contentView, let scrollView else { return nil }
        return contentView.convert(scrollView.contentView.bounds, from: scrollView.contentView)
    }

    var bottomIsVisible: Bool {
        guard let contentView, let visibleContent else { return false }
        let bottom = contentView.isFlipped ? contentView.bounds.maxY : contentView.bounds.minY
        return bottom >= visibleContent.minY - 3 && bottom <= visibleContent.maxY + 3
    }

    var topIsVisible: Bool {
        guard let contentView, let visibleContent else { return false }
        let top = contentView.isFlipped ? contentView.bounds.minY : contentView.bounds.maxY
        return top >= visibleContent.minY - 3 && top <= visibleContent.maxY + 3
    }

    var geometryDescription: String {
        guard let contentView, let scrollView, let document = scrollView.documentView else {
            return "missing content/scroll/document"
        }
        return "ready=\(readyCount), clip=\(scrollView.contentView.bounds), document=\(document.bounds), "
            + "documentFrame=\(document.frame), documentFlipped=\(document.isFlipped), "
            + "content=\(contentView.bounds), contentFrame=\(contentView.frame), "
            + "contentFlipped=\(contentView.isFlipped), visibleContent=\(String(describing: visibleContent))"
    }
}

private struct MarkdownReadingProbe: NSViewRepresentable {
    let recorder: MarkdownReadingRecorder

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        recorder.contentView = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

private struct MarkdownReadingFixtureView: View {
    let text: String
    let recorder: MarkdownReadingRecorder

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    MarkdownView(text: text, onPresentationReady: {
                        recorder.readyCount += 1
                        proxy.scrollTo("markdown-reading-bottom", anchor: .bottom)
                    }, bottomAnchorID: "markdown-reading-bottom")
                    .equatable()
                    .id("markdown-reading-top")
                    .background(MarkdownReadingProbe(recorder: recorder))
                    .font(.system(size: 15))
                    .lineSpacing(4)
                }
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(20)
            }
            .onAppear {
                recorder.scrollToEndpoint = { bottom in
                    proxy.scrollTo(bottom ? "markdown-reading-bottom" : "markdown-reading-top",
                                   anchor: bottom ? .bottom : .top)
                }
            }
            .onDisappear { recorder.scrollToEndpoint = nil }
        }
    }
}

private func markdownReadingFixture(characterCount: Int) -> String {
    let paragraph = "完成态长文阅读应保持当前位置，段落、列表、引用和代码按需布局。This paragraph checks lazy Markdown reading without changing the result text. "
    let section = "## 阅读章节\n\n" + String(repeating: paragraph, count: 4)
        + "\n\n- 第一项说明\n- 第二项包含 **强调** 和 `inline code`\n\n> 引用内容保持正常换行。\n\n"
        + "```swift\nlet result = [1, 2, 3].map { $0 * 2 }\nprint(result)\n```\n\n"
    let headers = (1...10).map { "Column \($0)" }.joined(separator: " | ")
    let separators = Array(repeating: "---", count: 10).joined(separator: " | ")
    let cells = (1...10).map { "Wide table cell \($0)" }.joined(separator: " | ")
    let tail = "\n\n```text\n" + String(repeating: "wide_code_identifier_", count: 40)
        + "\n```\n\n| " + headers + " |\n| " + separators + " |\n| " + cells
        + " |\n\nMARKDOWN READING FINAL SENTINEL\n"
    let bodyCount = characterCount - tail.count
    let wholeSections = bodyCount / section.count
    let remainder = bodyCount - wholeSections * section.count
    let padding = String(String(repeating: paragraph, count: remainder / paragraph.count + 1).prefix(remainder))
    return String(repeating: section, count: wholeSections) + padding + tail
}

@MainActor
func runMarkdownReadingRuntimeTests() async -> [String] {
    var failures: [String] = []

    func check(_ condition: Bool, _ size: Int, _ message: String) {
        if !condition { failures.append("Markdown reading (\(size) characters): " + message) }
    }

    func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(8)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    func settle(_ hosting: NSView, _ scroll: NSScrollView) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        var previous = NSRect.null
        var stableSamples = 0
        while Date() < deadline {
            hosting.layoutSubtreeIfNeeded()
            let sample = NSRect(origin: scroll.contentView.bounds.origin,
                                size: scroll.documentView?.bounds.size ?? .zero)
            if sample == previous { stableSamples += 1 } else { stableSamples = 0 }
            if stableSamples >= 8 { return true }
            previous = sample
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return false
    }

    func scroll(_ scroll: NSScrollView, fraction: CGFloat, recorder: MarkdownReadingRecorder) -> Bool {
        if fraction == 0 || fraction == 1 {
            guard let scrollToEndpoint = recorder.scrollToEndpoint else { return false }
            scrollToEndpoint(fraction == 1)
            return true
        }
        guard let document = scroll.documentView else { return false }
        let visible = document.convert(scroll.contentView.bounds, from: scroll.contentView)
        let distance = max(0, document.bounds.height - visible.height)
        let targetY = document.isFlipped
            ? document.bounds.minY + distance * fraction
            : document.bounds.maxY - visible.height - distance * fraction
        var origin = scroll.contentView.bounds.origin
        origin.y += targetY - visible.minY
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
        return true
    }

    func descendantScrollViews(_ view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? [])
            + view.subviews.flatMap { descendantScrollViews($0) }
    }

    for size in [10_000, 40_000, 100_000] {
        let recorder = MarkdownReadingRecorder()
        let text = markdownReadingFixture(characterCount: size)
        check(text.count == size, size, "fixture has the requested character count")
        let hosting = NSHostingView(rootView: MarkdownReadingFixtureView(text: text, recorder: recorder))
        hosting.frame = NSRect(x: 0, y: 0, width: 680, height: 600)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        let originalWidth = window.frame.width
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        let initialBottom = await waitUntil {
            hosting.layoutSubtreeIfNeeded()
            return recorder.readyCount >= 2 && recorder.bottomIsVisible
        }
        check(initialBottom, size, "initial presentation and its bottom anchor reach the viewport")
        guard let outerScroll = recorder.scrollView else {
            check(false, size, "the hosted Markdown uses a real enclosing NSScrollView")
            continue
        }
        check(await settle(hosting, outerScroll), size, "initial lazy layout settles")
        let initialReadyCount = recorder.readyCount
        check(initialReadyCount == 2, size, "presentation and first bottom appearance notify exactly once each (got \(initialReadyCount))")
        check(recorder.bottomIsVisible, size, "the final Markdown block stays reachable after initial layout")
        check((outerScroll.documentView?.bounds.height ?? 0) > outerScroll.contentView.bounds.height * 3,
              size, "the fixture requires enough vertical scrolling to recycle offscreen blocks")

        let horizontalScrolls = descendantScrollViews(hosting).filter {
            $0 !== outerScroll && ($0.documentView?.bounds.width ?? 0) > $0.contentView.bounds.width + 50
                && !$0.convert($0.bounds, to: outerScroll.contentView).intersection(outerScroll.contentView.bounds).isEmpty
        }
        check(horizontalScrolls.count >= 2, size, "wide code and the ten-column table expose their own visible horizontal scroll views")
        for nested in horizontalScrolls {
            check(nested.frame.width <= outerScroll.contentView.bounds.width + 1,
                  size, "horizontal content stays within the vertical viewport")
            let verticalOrigin = outerScroll.contentView.bounds.origin
            var nestedOrigin = nested.contentView.bounds.origin
            nestedOrigin.x = min(120, (nested.documentView?.bounds.width ?? 0) - nested.contentView.bounds.width)
            nested.contentView.scroll(to: nestedOrigin)
            nested.reflectScrolledClipView(nested.contentView)
            check(await settle(hosting, outerScroll), size, "horizontal scrolling settles")
            check(nested.contentView.bounds.minX > 0, size, "wide content can actually scroll horizontally")
            check(abs(outerScroll.contentView.bounds.minY - verticalOrigin.y) <= 1,
                  size, "horizontal reading does not move the vertical viewport")
        }

        for cycle in 1...2 {
            let beforeTop = recorder.geometryDescription
            check(scroll(outerScroll, fraction: 0, recorder: recorder), size, "the SwiftUI scroll proxy accepts the top target in cycle \(cycle)")
            let immediateTop = recorder.geometryDescription
            check(await settle(hosting, outerScroll), size, "top layout settles in cycle \(cycle)")
            check(recorder.topIsVisible && !recorder.bottomIsVisible, size,
                  "scrolling to the start removes the bottom anchor from the viewport in cycle \(cycle); "
                    + "before: \(beforeTop); immediate: \(immediateTop); settled: \(recorder.geometryDescription)")
            check(recorder.readyCount == initialReadyCount, size, "scrolling up does not publish ready again")

            check(scroll(outerScroll, fraction: 1, recorder: recorder), size, "the SwiftUI scroll proxy accepts the bottom target in cycle \(cycle)")
            check(await settle(hosting, outerScroll), size, "bottom layout settles in cycle \(cycle)")
            if !recorder.bottomIsVisible {
                check(scroll(outerScroll, fraction: 1, recorder: recorder), size, "the SwiftUI scroll proxy accepts the updated bottom target")
                check(await settle(hosting, outerScroll), size, "the updated lazy extent settles at the bottom")
            }
            check(recorder.bottomIsVisible, size, "returning through recycled blocks reaches the final block")
            check(recorder.readyCount == initialReadyCount, size,
                  "bottom reappearance must not notify ready or request another final scroll (got \(recorder.readyCount))")

            check(scroll(outerScroll, fraction: 0.45, recorder: recorder), size, "the native clip view accepts the middle target in cycle \(cycle)")
            check(await settle(hosting, outerScroll), size, "middle reading layout settles in cycle \(cycle)")
            let readingOrigin = outerScroll.contentView.bounds.origin
            check(!recorder.bottomIsVisible, size, "the reader can stop in the middle after revisiting the bottom")
            try? await Task.sleep(nanoseconds: 350_000_000)
            hosting.layoutSubtreeIfNeeded()
            check(abs(outerScroll.contentView.bounds.minY - readingOrigin.y) <= 1 && !recorder.bottomIsVisible,
                  size, "idle presentation does not steal the settled reading position")
            check(recorder.readyCount == initialReadyCount, size, "ready count stays unchanged while reading")
        }
        check(abs(window.frame.width - originalWidth) <= 1, size, "code and table layout do not widen the host window")
        check((outerScroll.documentView?.bounds.width ?? .infinity) <= outerScroll.contentView.bounds.width + 1,
              size, "the main document does not acquire horizontal overflow")
    }
    return failures
}
