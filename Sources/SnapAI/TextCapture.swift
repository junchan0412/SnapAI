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

    /// 当前进程是否已被授予辅助功能权限
    static func hasAccessibilityPermission(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 异步获取选中文字。结果在主线程(MainActor)回调。
    static func capture(preferAX: Bool, completion: @escaping @MainActor (String?) -> Void) {
        captureDetailed(preferAX: preferAX) { outcome in
            completion(outcome.usableText)
        }
    }

    static func captureDetailed(preferAX: Bool, completion: @escaping @MainActor (TextCaptureOutcome) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var outcome = TextCaptureOutcome(text: nil,
                                             method: nil,
                                             accessibilityAttempted: preferAX,
                                             clipboardAttempted: false,
                                             failureReason: nil,
                                             pasteboardReasonCode: nil,
                                             clipboardWaitAttempts: 0)
            if preferAX {
                let result = captureViaAX()
                if usableCapturedText(result) != nil {
                    outcome.text = result
                    outcome.method = .accessibility
                } else {
                    outcome.failureReason = .accessibilityEmptySelection
                }
            }
            if outcome.usableText == nil {
                outcome.clipboardAttempted = true
                let copyResult = captureViaCopyDetailed()
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

    private static func captureViaAX() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let element = focused,
              isAXUIElementRef(element) else {
            return nil
        }
        let axElement = element as! AXUIElement

        var selected: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement,
                                         kAXSelectedTextAttribute as CFString,
                                         &selected) == .success,
           let text = selected as? String, !text.isEmpty {
            storeSelectionSnapshot(element: axElement, selectedText: text)
            return text
        }
        clearSelectionSnapshot()
        return nil
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
        guard
              AXValueGetType(axValue) == .cfRange else {
            clearSelectionSnapshot()
            return
        }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            clearSelectionSnapshot()
            return
        }
        let snapshot = TextSelectionSnapshot(element: element,
                                             selectedRange: range,
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

    private static func captureViaCopyDetailed() -> (text: String?,
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

        sendCmdC()

        // 轮询等待剪贴板更新(最多约 400ms)
        var attempts = 0
        while pasteboard.changeCount == previousChangeCount && attempts < 40 {
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
