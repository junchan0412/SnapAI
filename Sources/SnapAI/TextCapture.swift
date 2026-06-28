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
        DispatchQueue.global(qos: .userInitiated).async {
            var result: String? = nil
            if preferAX {
                result = captureViaAX()
            }
            if result == nil || result?.isEmpty == true {
                result = captureViaCopy()
            }
            let final = usableCapturedText(result)
            Task { @MainActor in
                completion(final)
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
              let element = focused else {
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
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
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

    // MARK: - 模拟复制兜底

    private static func captureViaCopy() -> String? {
        clearSelectionSnapshot()
        let pasteboard = NSPasteboard.general
        let previousItems = snapshotPasteboard(pasteboard)
        let previousChangeCount = pasteboard.changeCount

        sendCmdC()

        // 轮询等待剪贴板更新(最多约 400ms)
        var attempts = 0
        while pasteboard.changeCount == previousChangeCount && attempts < 40 {
            usleep(10_000) // 10ms
            attempts += 1
        }

        guard pasteboard.changeCount != previousChangeCount else {
            return nil
        }

        let captured = pasteboard.string(forType: .string)

        // 还原剪贴板,避免污染用户原有内容
        restorePasteboard(pasteboard, items: previousItems)

        return captured
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

    static func snapshotPasteboard(_ pb: NSPasteboard) -> [[String: Data]] {
        var snapshot: [[String: Data]] = []
        for item in pb.pasteboardItems ?? [] {
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type.rawValue] = data
                }
            }
            snapshot.append(dict)
        }
        return snapshot
    }

    static func restorePasteboard(_ pb: NSPasteboard, items: [[String: Data]]) {
        pb.clearContents()
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
}
