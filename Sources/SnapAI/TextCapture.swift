import AppKit
import ApplicationServices
import Carbon.HIToolbox

struct TextSelectionSnapshot {
    fileprivate let element: AXUIElement
    let selectedRange: CFRange
    let selectedText: String

    func restoreSelection() -> Bool {
        var range = selectedRange
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        ) == .success
    }
}

struct PasteboardSnapshot: Equatable {
    static let defaultLimits = PasteboardSnapshotLimits()

    var items: [[String: Data]]
    var isComplete: Bool
    var reasonCode: String
    var totalByteCount: Int
    var itemCount: Int
    var typeCount: Int

    var canRestore: Bool {
        isComplete
    }

    var recoveryMessage: String {
        guard !isComplete else { return "剪贴板可安全恢复" }
        return "当前剪贴板内容过大或格式过多,为避免丢失用户剪贴板,已取消自动粘贴。请手动复制结果后粘贴。"
    }

    var undoRecoveryMessage: String {
        guard !isComplete else { return "剪贴板可安全恢复" }
        return "当前剪贴板内容过大或格式过多,为避免丢失用户剪贴板,已取消自动撤销。请在目标应用中使用系统撤销,或手动恢复。"
    }

    static func complete(items: [[String: Data]],
                         totalByteCount: Int,
                         itemCount: Int,
                         typeCount: Int) -> PasteboardSnapshot {
        PasteboardSnapshot(items: items,
                           isComplete: true,
                           reasonCode: "complete",
                           totalByteCount: max(0, totalByteCount),
                           itemCount: max(0, itemCount),
                           typeCount: max(0, typeCount))
    }

    static func incomplete(reasonCode: String,
                           totalByteCount: Int,
                           itemCount: Int,
                           typeCount: Int) -> PasteboardSnapshot {
        PasteboardSnapshot(items: [],
                           isComplete: false,
                           reasonCode: reasonCode,
                           totalByteCount: max(0, totalByteCount),
                           itemCount: max(0, itemCount),
                           typeCount: max(0, typeCount))
    }
}

struct PasteboardSnapshotLimits: Equatable {
    var maxItemCount: Int = 32
    var maxTypeCount: Int = 128
    var maxTotalByteCount: Int = 64 * 1024 * 1024
}

enum TextCaptureMethod: String, Equatable {
    case accessibility = "accessibility"
    case clipboard = "clipboard"
    case service = "service"
}

enum TextCaptureFailureReason: String, Equatable {
    case accessibilityEmptySelection = "accessibility-empty-selection"
    case pasteboardSnapshotUnsafe = "pasteboard-snapshot-unsafe"
    case clipboardUnchanged = "clipboard-unchanged"
    case clipboardEmpty = "clipboard-empty"
}

struct TextCaptureOutcome: Equatable {
    var text: String?
    var method: TextCaptureMethod?
    var accessibilityAttempted: Bool
    var clipboardAttempted: Bool
    var failureReason: TextCaptureFailureReason?
    var pasteboardReasonCode: String?
    var clipboardWaitAttempts: Int

    var usableText: String? {
        TextCapture.usableCapturedText(text)
    }
}

/// 取词模块。
/// 策略:优先用 Accessibility API 直接读取焦点元素的 kAXSelectedTextAttribute(无感、不污染剪贴板);
/// 失败时回退到模拟 ⌘C 复制再读剪贴板。
enum TextCapture {
    private static let snapshotQueue = DispatchQueue(label: "com.snapai.text-selection-snapshot")
    private static var recentSnapshot: TextSelectionSnapshot?
    static let targetActivationWaitMicroseconds: useconds_t = 120_000
    static let transientMenuDismissWaitMicroseconds: useconds_t = 60_000
    static let clipboardChangePollLimit = 80

    /// 当前进程是否已被授予辅助功能权限
    static func hasAccessibilityPermission(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 异步获取选中文字。结果在主线程(MainActor)回调。
    static func capture(preferAX: Bool,
                        targetApp: NSRunningApplication? = nil,
                        completion: @escaping @MainActor (String?) -> Void) {
        captureDetailed(preferAX: preferAX, targetApp: targetApp) { outcome in
            completion(outcome.usableText)
        }
    }

    static func captureDetailed(preferAX: Bool,
                                targetApp: NSRunningApplication? = nil,
                                completion: @escaping @MainActor (TextCaptureOutcome) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var outcome = TextCaptureOutcome(text: nil,
                                             method: nil,
                                             accessibilityAttempted: preferAX,
                                             clipboardAttempted: false,
                                             failureReason: nil,
                                             pasteboardReasonCode: nil,
                                             clipboardWaitAttempts: 0)
            if preferAX {
                let result = captureViaAX(targetApp: targetApp)
                if usableCapturedText(result) != nil {
                    outcome.text = result
                    outcome.method = .accessibility
                } else {
                    outcome.failureReason = .accessibilityEmptySelection
                }
            }
            if shouldRetryAccessibilityAfterTargetActivation(preferAX: preferAX,
                                                              capturedText: outcome.text,
                                                              targetPID: targetApp?.processIdentifier,
                                                              targetIsTerminated: targetApp?.isTerminated ?? true) {
                if activateTargetForCapture(targetApp) {
                    usleep(targetActivationWaitMicroseconds)
                    let retry = captureViaAX(targetApp: targetApp)
                    if usableCapturedText(retry) != nil {
                        outcome.text = retry
                        outcome.method = .accessibility
                        outcome.failureReason = nil
                    }
                }
            }
            if outcome.usableText == nil {
                outcome.clipboardAttempted = true
                let copyResult = captureViaCopyDetailed(targetApp: targetApp)
                outcome.text = copyResult.text
                outcome.clipboardWaitAttempts = copyResult.waitAttempts
                outcome.pasteboardReasonCode = copyResult.pasteboardReasonCode
                if usableCapturedText(copyResult.text) != nil {
                    outcome.method = .clipboard
                    outcome.failureReason = nil
                } else {
                    outcome.failureReason = copyResult.failureReason
                }
            }
            Task { @MainActor in
                completion(outcome)
            }
        }
    }

    static func usableCapturedText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? text : nil
    }

    // MARK: - AX 直读

    static func selectedTextViaAX() -> String? {
        captureViaAX()
    }

    static func recentSelectionSnapshot(matching text: String) -> TextSelectionSnapshot? {
        snapshotQueue.sync {
            guard recentSnapshot?.selectedText == text else { return nil }
            return recentSnapshot
        }
    }

    static func clearRecentSelectionSnapshot() {
        clearSelectionSnapshot()
    }

    private static func captureViaAX(targetApp: NSRunningApplication? = nil) -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWide,
                                         kAXFocusedUIElementAttribute as CFString,
                                         &focused) == .success,
           let element = focused,
           isAXUIElementRef(element) {
            let axElement = element as! AXUIElement
            var visited = AXTraversalCounter()
            if let text = selectedText(in: axElement, depth: 2, visited: &visited) {
                return text
            }
        }

        if let targetApp,
           shouldActivateTargetForCapture(targetPID: targetApp.processIdentifier,
                                          currentPID: ProcessInfo.processInfo.processIdentifier,
                                          isTerminated: targetApp.isTerminated) {
            let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)
            var visited = AXTraversalCounter()
            if let text = selectedText(in: appElement, depth: 5, visited: &visited) {
                return text
            }
        }
        clearSelectionSnapshot()
        return nil
    }

    private struct AXTraversalCounter {
        var count = 0
    }

    private static func selectedText(in element: AXUIElement,
                                     depth: Int,
                                     visited: inout AXTraversalCounter) -> String? {
        guard visited.count < 90 else { return nil }
        visited.count += 1

        var selected: CFTypeRef?
        if AXUIElementCopyAttributeValue(element,
                                         kAXSelectedTextAttribute as CFString,
                                         &selected) == .success,
           let text = selected as? String,
           usableCapturedText(text) != nil {
            storeSelectionSnapshot(element: element, selectedText: text)
            return text
        }
        if let text = selectedTextFromValueRange(in: element) {
            return text
        }

        guard depth > 0 else { return nil }

        for attribute in [
            kAXFocusedUIElementAttribute as CFString,
            kAXFocusedWindowAttribute as CFString
        ] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
               let rawValue = value,
               isAXUIElementRef(rawValue) {
                let child = rawValue as! AXUIElement
                if let text = selectedText(in: child, depth: depth - 1, visited: &visited) {
                    return text
                }
            }
        }

        for attribute in [
            kAXChildrenAttribute as CFString,
            "AXVisibleChildren" as CFString
        ] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
                  let children = value as? [Any] else {
                continue
            }
            for childValue in children {
                let rawChild = childValue as CFTypeRef
                guard isAXUIElementRef(rawChild) else { continue }
                let child = rawChild as! AXUIElement
                if let text = selectedText(in: child, depth: depth - 1, visited: &visited) {
                    return text
                }
            }
        }

        return nil
    }

    private static func selectedTextFromValueRange(in element: AXUIElement) -> String? {
        guard let range = selectedRange(in: element),
              let value = stringValue(in: element),
              let text = selectedSubstring(in: value, range: range) else {
            return nil
        }
        storeSelectionSnapshot(element: element,
                               selectedText: text,
                               selectedRange: range)
        return text
    }

    private static func selectedRange(in element: AXUIElement) -> CFRange? {
        if let range = rangeAttribute(kAXSelectedTextRangeAttribute as CFString, in: element),
           range.length > 0 {
            return range
        }
        var ranges: CFTypeRef?
        if AXUIElementCopyAttributeValue(element,
                                         "AXSelectedTextRanges" as CFString,
                                         &ranges) == .success,
           let rawRanges = ranges as? [Any] {
            for rawRange in rawRanges {
                let value = rawRange as CFTypeRef
                if isAXValueRef(value),
                   let range = cfRange(from: value),
                   range.length > 0 {
                    return range
                }
            }
        }
        return nil
    }

    private static func rangeAttribute(_ attribute: CFString, in element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let rawValue = value,
              isAXValueRef(rawValue) else {
            return nil
        }
        return cfRange(from: rawValue)
    }

    private static func cfRange(from value: CFTypeRef) -> CFRange? {
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func stringValue(in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXValueAttribute as CFString,
                                            &value) == .success else {
            return nil
        }
        return value as? String
    }

    static func selectedSubstring(in value: String, range: CFRange) -> String? {
        guard range.location >= 0,
              range.length > 0 else {
            return nil
        }
        let endOffset = range.location + range.length
        guard endOffset >= range.location,
              endOffset <= value.utf16.count else {
            return nil
        }
        let utf16Start = value.utf16.index(value.utf16.startIndex,
                                          offsetBy: range.location)
        let utf16End = value.utf16.index(utf16Start,
                                        offsetBy: range.length)
        guard let start = String.Index(utf16Start, within: value),
              let end = String.Index(utf16End, within: value) else {
            return nil
        }
        return usableCapturedText(String(value[start..<end]))
    }

    private static func storeSelectionSnapshot(element: AXUIElement, selectedText: String) {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXSelectedTextRangeAttribute as CFString,
                                            &rangeValue) == .success,
              let rawValue = rangeValue,
              isAXValueRef(rawValue) else {
            clearSelectionSnapshot()
            return
        }
        let axValue = rawValue as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            clearSelectionSnapshot()
            return
        }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            clearSelectionSnapshot()
            return
        }
        storeSelectionSnapshot(element: element,
                               selectedText: selectedText,
                               selectedRange: range)
    }

    private static func storeSelectionSnapshot(element: AXUIElement,
                                               selectedText: String,
                                               selectedRange: CFRange) {
        let snapshot = TextSelectionSnapshot(element: element,
                                             selectedRange: selectedRange,
                                             selectedText: selectedText)
        snapshotQueue.sync {
            recentSnapshot = snapshot
        }
    }

    private static func clearSelectionSnapshot() {
        snapshotQueue.sync {
            recentSnapshot = nil
        }
    }

    static func isAXUIElementRef(_ value: CFTypeRef) -> Bool {
        CFGetTypeID(value) == AXUIElementGetTypeID()
    }

    static func isAXValueRef(_ value: CFTypeRef) -> Bool {
        CFGetTypeID(value) == AXValueGetTypeID()
    }

    // MARK: - 模拟复制兜底

    private static func captureViaCopy() -> String? {
        captureViaCopyDetailed().text
    }

    private static func captureViaCopyDetailed(targetApp: NSRunningApplication? = nil) -> (text: String?,
                                                                                           failureReason: TextCaptureFailureReason?,
                                                                                           pasteboardReasonCode: String?,
                                                                                           waitAttempts: Int) {
        clearSelectionSnapshot()
        let pasteboard = NSPasteboard.general
        let previousSnapshot = snapshotPasteboard(pasteboard)
        guard previousSnapshot.canRestore else {
            return (nil, .pasteboardSnapshotUnsafe, previousSnapshot.reasonCode, 0)
        }
        let previousChangeCount = pasteboard.changeCount
        let frontmostPIDBeforeCopy = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let shouldDismissTransientMenu = shouldDismissTransientMenusBeforeCopy(
            targetPID: targetApp?.processIdentifier,
            frontmostPID: frontmostPIDBeforeCopy
        )

        if let targetApp,
           activateTargetForCapture(targetApp) {
            usleep(targetActivationWaitMicroseconds)
        }
        if shouldDismissTransientMenu {
            sendEscape()
            usleep(transientMenuDismissWaitMicroseconds)
        }
        sendCmdC()

        // 轮询等待剪贴板更新(最多约 800ms),给右键菜单和复杂编辑控件更多响应时间。
        var attempts = 0
        while pasteboard.changeCount == previousChangeCount && attempts < clipboardChangePollLimit {
            usleep(10_000) // 10ms
            attempts += 1
        }

        guard pasteboard.changeCount != previousChangeCount else {
            return (nil, .clipboardUnchanged, nil, attempts)
        }

        let capturedChangeCount = pasteboard.changeCount
        let captured = pasteboard.string(forType: .string)

        // 还原剪贴板,避免污染用户原有内容
        restorePasteboardIfUnchanged(pasteboard,
                                     snapshot: previousSnapshot,
                                     expectedChangeCount: capturedChangeCount)

        if usableCapturedText(captured) == nil {
            return (captured, .clipboardEmpty, nil, attempts)
        }
        return (captured, nil, nil, attempts)
    }

    static func shouldActivateTargetForCapture(targetPID: pid_t?,
                                               currentPID: pid_t = ProcessInfo.processInfo.processIdentifier,
                                               isTerminated: Bool) -> Bool {
        guard let targetPID,
              targetPID > 0,
              !isTerminated,
              targetPID != currentPID else {
            return false
        }
        return true
    }

    static func shouldRetryAccessibilityAfterTargetActivation(preferAX: Bool,
                                                              capturedText: String?,
                                                              targetPID: pid_t?,
                                                              targetIsTerminated: Bool,
                                                              currentPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        guard preferAX,
              usableCapturedText(capturedText) == nil else {
            return false
        }
        return shouldActivateTargetForCapture(targetPID: targetPID,
                                              currentPID: currentPID,
                                              isTerminated: targetIsTerminated)
    }

    static func shouldDismissTransientMenusBeforeCopy(targetPID: pid_t?,
                                                      frontmostPID: pid_t?,
                                                      currentPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        guard let targetPID,
              targetPID > 0,
              targetPID != currentPID,
              let frontmostPID,
              frontmostPID != targetPID else {
            return false
        }
        return true
    }

    @discardableResult
    static func activateTargetForCapture(_ targetApp: NSRunningApplication?,
                                         currentPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        guard let targetApp,
              shouldActivateTargetForCapture(targetPID: targetApp.processIdentifier,
                                             currentPID: currentPID,
                                             isTerminated: targetApp.isTerminated) else {
            return false
        }
        if Thread.isMainThread {
            _ = targetApp.activate()
            return true
        }
        DispatchQueue.main.sync {
            _ = targetApp.activate()
        }
        return true
    }

    private static func sendCmdC() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let cKey = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func sendEscape() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let escapeKey = CGKeyCode(kVK_Escape)
        CGEvent(keyboardEventSource: source, virtualKey: escapeKey, keyDown: true)?
            .post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: escapeKey, keyDown: false)?
            .post(tap: .cghidEventTap)
    }

    /// 模拟 ⌘V 粘贴(用于把结果替换回原文位置)
    static func sendCmdV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func sendRightArrow() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let right = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_RightArrow), keyDown: true)
        right?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_RightArrow), keyDown: false)?
            .post(tap: .cghidEventTap)
    }

    static func sendShiftLeftArrow(repeat count: Int) {
        guard count > 0,
              let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let cappedCount = min(count, 20_000)
        for _ in 0..<cappedCount {
            let down = CGEvent(keyboardEventSource: source,
                               virtualKey: CGKeyCode(kVK_LeftArrow),
                               keyDown: true)
            down?.flags = .maskShift
            let up = CGEvent(keyboardEventSource: source,
                             virtualKey: CGKeyCode(kVK_LeftArrow),
                             keyDown: false)
            up?.flags = .maskShift
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    static func pasteboardSnapshotRejectionReason(itemCount: Int,
                                                  typeCount: Int,
                                                  totalByteCount: Int,
                                                  limits: PasteboardSnapshotLimits = PasteboardSnapshot.defaultLimits) -> String? {
        if itemCount > limits.maxItemCount { return "too-many-items" }
        if typeCount > limits.maxTypeCount { return "too-many-types" }
        if totalByteCount > limits.maxTotalByteCount { return "too-large" }
        return nil
    }

    static func snapshotPasteboard(_ pb: NSPasteboard,
                                   limits: PasteboardSnapshotLimits = PasteboardSnapshot.defaultLimits) -> PasteboardSnapshot {
        var snapshot: [[String: Data]] = []
        var totalByteCount = 0
        var typeCount = 0
        let pasteboardItems = pb.pasteboardItems ?? []
        if let reason = pasteboardSnapshotRejectionReason(itemCount: pasteboardItems.count,
                                                          typeCount: 0,
                                                          totalByteCount: 0,
                                                          limits: limits) {
            return .incomplete(reasonCode: reason,
                               totalByteCount: 0,
                               itemCount: pasteboardItems.count,
                               typeCount: 0)
        }
        for item in pasteboardItems {
            var dict: [String: Data] = [:]
            for type in item.types {
                typeCount += 1
                if let reason = pasteboardSnapshotRejectionReason(itemCount: pasteboardItems.count,
                                                                  typeCount: typeCount,
                                                                  totalByteCount: totalByteCount,
                                                                  limits: limits) {
                    return .incomplete(reasonCode: reason,
                                       totalByteCount: totalByteCount,
                                       itemCount: pasteboardItems.count,
                                       typeCount: typeCount)
                }
                if let data = item.data(forType: type) {
                    totalByteCount += data.count
                    if let reason = pasteboardSnapshotRejectionReason(itemCount: pasteboardItems.count,
                                                                      typeCount: typeCount,
                                                                      totalByteCount: totalByteCount,
                                                                      limits: limits) {
                        return .incomplete(reasonCode: reason,
                                           totalByteCount: totalByteCount,
                                           itemCount: pasteboardItems.count,
                                           typeCount: typeCount)
                    }
                    dict[type.rawValue] = data
                }
            }
            snapshot.append(dict)
        }
        return .complete(items: snapshot,
                         totalByteCount: totalByteCount,
                         itemCount: pasteboardItems.count,
                         typeCount: typeCount)
    }

    static func restorePasteboard(_ pb: NSPasteboard, snapshot: PasteboardSnapshot) {
        guard snapshot.canRestore else { return }
        pb.clearContents()
        let items = snapshot.items
        guard !items.isEmpty else { return }
        var newItems: [NSPasteboardItem] = []
        for dict in items {
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            newItems.append(item)
        }
        pb.writeObjects(newItems)
    }

    static func shouldRestorePasteboard(expectedChangeCount: Int,
                                        currentChangeCount: Int) -> Bool {
        currentChangeCount == expectedChangeCount
    }

    @discardableResult
    static func restorePasteboardIfUnchanged(_ pb: NSPasteboard,
                                             snapshot: PasteboardSnapshot,
                                             expectedChangeCount: Int) -> Bool {
        guard snapshot.canRestore else { return false }
        guard shouldRestorePasteboard(expectedChangeCount: expectedChangeCount,
                                      currentChangeCount: pb.changeCount) else {
            return false
        }
        restorePasteboard(pb, snapshot: snapshot)
        return true
    }
}
