import AppKit
import Foundation
import SnapAILogic

@MainActor
final class ResultStreamingCoordinator {
    private var lifecycle = ResultStreamingLifecycle()
    private var typewriterTimer: Timer?
    private var charactersPerTick = 0
    private var tickInterval: TimeInterval = 0
    private var onOutputChunk: ((String) -> Void)?
    private var onDrained: (() -> Void)?

    var completeText: String { lifecycle.completeText }
    var thinkingText: String { lifecycle.thinkingText }
    private(set) var usesTypewriter = false

    var isPresentationScheduled: Bool { typewriterTimer != nil }

    deinit {
        typewriterTimer?.invalidate()
    }

    func reset() {
        stopTimer()
        lifecycle.reset()
        usesTypewriter = false
    }

    func begin(speed: TypewriterSpeed,
               reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
               onOutputChunk: @escaping (String) -> Void,
               onDrained: @escaping () -> Void) {
        stopTimer()
        usesTypewriter = speed != .off && !reduceMotion
        guard usesTypewriter else { return }

        charactersPerTick = speed.charsPerTick
        tickInterval = max(1.0 / 60.0, speed.tickInterval)
        charactersPerTick = max(charactersPerTick, Int((Double(speed.charsPerTick) * tickInterval / speed.tickInterval).rounded()))
        self.onOutputChunk = onOutputChunk
        self.onDrained = onDrained
        schedulePresentationIfNeeded()
    }

    private func schedulePresentationIfNeeded() {
        guard usesTypewriter, typewriterTimer == nil,
              onDrained != nil, lifecycle.needsPresentationTick else { return }
        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // 允许系统合并相邻 timer 唤醒,减少与滚动/绘制争抢主线程的硬抖动。
        timer.tolerance = min(0.008, tickInterval * 0.25)
        RunLoop.main.add(timer, forMode: .common)
        typewriterTimer = timer
    }

    func appendContentToken(_ token: String, extractsThinkTags: Bool) -> String? {
        let immediateText = lifecycle.appendContentToken(token,
                                                          extractsThinkTags: extractsThinkTags,
                                                          usesTypewriter: usesTypewriter)
        schedulePresentationIfNeeded()
        return immediateText
    }

    @discardableResult
    func appendExternalThinking(_ text: String) -> String {
        lifecycle.appendExternalThinking(text)
    }

    func finish() -> String? {
        let immediateText = lifecycle.finish(usesTypewriter: usesTypewriter)
        if usesTypewriter {
            let remainingTicks = max(1, Int(0.6 / tickInterval))
            charactersPerTick = max(charactersPerTick,
                                    (lifecycle.pendingCharacterCount + remainingTicks - 1) / remainingTicks)
        }
        // 保持异步结束，让调用方先处理诊断或取消失败请求的 drain。
        schedulePresentationIfNeeded()
        return immediateText
    }

    @discardableResult
    func revealImmediately() -> String {
        stopAndDiscardPendingPresentation()
        usesTypewriter = false
        return completeText
    }

    func stopAndDiscardPendingPresentation() {
        stopTimer()
        lifecycle.discardPendingPresentation()
    }

    private func tick() {
        switch lifecycle.dequeue(maxCharacters: charactersPerTick) {
        case .waiting:
            pauseTimer()
        case .chunk(let text):
            onOutputChunk?(text)
            if !lifecycle.needsPresentationTick { pauseTimer() }
        case .finished:
            let completion = onDrained
            stopTimer()
            completion?()
        }
    }

    private func stopTimer() {
        pauseTimer()
        onOutputChunk = nil
        onDrained = nil
        charactersPerTick = 0
        tickInterval = 0
    }

    private func pauseTimer() {
        typewriterTimer?.invalidate()
        typewriterTimer = nil
    }
}
