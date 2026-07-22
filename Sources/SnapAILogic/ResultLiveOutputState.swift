import Combine
import Foundation

public struct ResultDiagnosticTextSnapshot: Equatable {
    public var fullText: String
    public var briefText: String

    public init(fullText: String = "", briefText: String = "") {
        self.fullText = fullText
        self.briefText = briefText
    }

    public static let empty = ResultDiagnosticTextSnapshot()
}

/// 结果输出状态。
/// 高频 append 会在当前 runloop 合并为一次发布,避免打字机/流式 token 连续触发整页 invalidation。
public final class ResultOutputState: ObservableObject {
    @Published public private(set) var text: String

    private var pendingAppend = ""
    private var flushScheduled = false

    public init(text: String = "") {
        self.text = text
    }

    @discardableResult
    public func replace(with text: String) -> Bool {
        flushPending(publishIfNeeded: false)
        guard self.text != text else { return false }
        self.text = text
        return true
    }

    /// 追加流式可见文本。连续 append 会合并到下一次主线程 flush。
    @discardableResult
    public func append(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        pendingAppend.append(contentsOf: text)
        scheduleFlush()
        return true
    }

    /// 立即冲刷挂起的增量(路由切换/结束/取消前调用,保证观测到完整文本)。
    public func flush() {
        flushPending(publishIfNeeded: true)
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        // 合并同一 runloop 内的多次 append,显著降低 SwiftUI 观察者刷新频率。
        DispatchQueue.main.async { [weak self] in
            self?.flushPending(publishIfNeeded: true)
        }
    }

    private func flushPending(publishIfNeeded: Bool) {
        flushScheduled = false
        guard !pendingAppend.isEmpty else { return }
        let text = pendingAppend
        pendingAppend = ""
        // 即使合并多个 chunk,最终也通过同一增量发布语句更新观察者。
        self.text.append(contentsOf: text)
        _ = publishIfNeeded
    }
}

public final class ResultThinkingState: ObservableObject {
    @Published public private(set) var text: String

    private var pendingText: String?
    private var flushScheduled = false

    public init(text: String = "") {
        self.text = text
    }

    @discardableResult
    public func replace(with text: String) -> Bool {
        // 取消挂起更新,以最新整段为准。
        pendingText = nil
        flushScheduled = false
        guard self.text != text else { return false }
        self.text = text
        return true
    }

    /// 高频 thinking 增量用合并发布,避免每个 token 都触发 Disclosure 区域重绘。
    @discardableResult
    public func replaceCoalesced(with text: String) -> Bool {
        guard self.text != text else {
            pendingText = nil
            return false
        }
        if pendingText == text { return true }
        pendingText = text
        scheduleFlush()
        return true
    }

    public func flush() {
        flushPending()
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushPending()
        }
    }

    private func flushPending() {
        flushScheduled = false
        guard let pendingText else { return }
        self.pendingText = nil
        if text != pendingText {
            text = pendingText
        }
    }
}
