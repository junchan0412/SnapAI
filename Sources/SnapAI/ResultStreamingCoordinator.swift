import Foundation
import SnapAILogic

@MainActor
final class ResultStreamingCoordinator {
    private var lifecycle = ResultStreamingLifecycle()
    private var typewriterTimer: Timer?
    private var charactersPerTick = 0
    private var onOutputChunk: ((String) -> Void)?
    private var onDrained: (() -> Void)?

    var completeText: String { lifecycle.completeText }
    var thinkingText: String { lifecycle.thinkingText }
    private(set) var usesTypewriter = false

    func reset() {
        stopTimer()
        lifecycle.reset()
        usesTypewriter = false
    }

    func begin(speed: TypewriterSpeed,
               onOutputChunk: @escaping (String) -> Void,
               onDrained: @escaping () -> Void) {
        stopTimer()
        usesTypewriter = speed != .off
        guard usesTypewriter else { return }

        charactersPerTick = speed.charsPerTick
        self.onOutputChunk = onOutputChunk
        self.onDrained = onDrained

        let interval = speed.tickInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // 允许系统合并相邻 timer 唤醒,减少与滚动/绘制争抢主线程的硬抖动。
        timer.tolerance = min(0.008, interval * 0.25)
        RunLoop.main.add(timer, forMode: .common)
        typewriterTimer = timer
    }

    func appendContentToken(_ token: String, extractsThinkTags: Bool) -> String? {
        lifecycle.appendContentToken(token,
                                     extractsThinkTags: extractsThinkTags,
                                     usesTypewriter: usesTypewriter)
    }

    @discardableResult
    func appendExternalThinking(_ text: String) -> String {
        lifecycle.appendExternalThinking(text)
    }

    func finish() -> String? {
        lifecycle.finish(usesTypewriter: usesTypewriter)
    }

    func stopAndDiscardPendingPresentation() {
        stopTimer()
        lifecycle.discardPendingPresentation()
    }

    private func tick() {
        switch lifecycle.dequeue(maxCharacters: charactersPerTick) {
        case .waiting:
            break
        case .chunk(let text):
            onOutputChunk?(text)
        case .finished:
            let completion = onDrained
            stopTimer()
            completion?()
        }
    }

    private func stopTimer() {
        typewriterTimer?.invalidate()
        typewriterTimer = nil
        onOutputChunk = nil
        onDrained = nil
        charactersPerTick = 0
    }
}
