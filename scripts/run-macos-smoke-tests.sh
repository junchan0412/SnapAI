#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

RUN_LOGIC=1

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-logic)
      RUN_LOGIC=0
      ;;
    -h|--help)
      echo "Usage: scripts/run-macos-smoke-tests.sh [--skip-logic]"
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

step() {
  echo ""
  echo "==> $1"
}

step "检查逻辑 target 边界"
scripts/check-logic-symlinks.sh

if [ "$RUN_LOGIC" -eq 1 ]; then
  step "运行逻辑测试"
  scripts/run-logic-tests.sh
fi

step "探测 macOS 剪贴板与隐私权限"
SWIFT_FILE=$(mktemp "${TMPDIR:-/tmp}/snapai-macos-smoke.XXXXXX.swift")
trap 'rm -f "$SWIFT_FILE"' EXIT

cat > "$SWIFT_FILE" <<'SWIFT'
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

struct PasteboardItemSnapshot {
    var values: [(NSPasteboard.PasteboardType, Data)]
}

let pasteboard = NSPasteboard.general
let originalItems = pasteboard.pasteboardItems ?? []
let snapshot = originalItems.map { item in
    PasteboardItemSnapshot(values: item.types.compactMap { type in
        item.data(forType: type).map { (type, $0) }
    })
}

func restorePasteboard() {
    pasteboard.clearContents()
    let items = snapshot.compactMap { snapshot -> NSPasteboardItem? in
        guard !snapshot.values.isEmpty else { return nil }
        let item = NSPasteboardItem()
        for (type, data) in snapshot.values {
            item.setData(data, forType: type)
        }
        return item
    }
    if !items.isEmpty {
        pasteboard.writeObjects(items)
    }
}

defer { restorePasteboard() }

let marker = "SnapAI macOS smoke \(UUID().uuidString)"
pasteboard.clearContents()
guard pasteboard.setString(marker, forType: .string),
      pasteboard.string(forType: .string) == marker else {
    fputs("error: pasteboard string roundtrip failed\n", stderr)
    exit(1)
}

let accessibilityTrusted = AXIsProcessTrusted()
let screenRecordingGranted = CGPreflightScreenCaptureAccess()
var hotKeyRef: EventHotKeyRef?
var hotKeyHandlerRef: EventHandlerRef?
let hotKeyTriggered = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
hotKeyTriggered.initialize(to: false)
defer {
    hotKeyTriggered.deinitialize(count: 1)
    hotKeyTriggered.deallocate()
}
let hotKeyID = EventHotKeyID(signature: OSType(0x534E4150), id: UInt32(19))
let hotKeyEventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                    eventKind: UInt32(kEventHotKeyPressed))
let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
    guard let event, let userData else { return noErr }
    var receivedID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &receivedID)
    if status == noErr,
       receivedID.signature == OSType(0x534E4150),
       receivedID.id == UInt32(19) {
        userData.assumingMemoryBound(to: Bool.self).pointee = true
    }
    return noErr
}, 1, [hotKeyEventSpec], hotKeyTriggered, &hotKeyHandlerRef)
let hotKeyStatus = RegisterEventHotKey(UInt32(kVK_F19),
                                       UInt32(cmdKey | optionKey | shiftKey),
                                       hotKeyID,
                                       GetApplicationEventTarget(),
                                       0,
                                       &hotKeyRef)
var hotKeyDispatchStatus: OSStatus = OSStatus(eventNotHandledErr)
if handlerStatus == noErr, hotKeyStatus == noErr {
    var hotKeyEvent: EventRef?
    var dispatchID = hotKeyID
    hotKeyDispatchStatus = CreateEvent(nil,
                                       OSType(kEventClassKeyboard),
                                       UInt32(kEventHotKeyPressed),
                                       GetCurrentEventTime(),
                                       0,
                                       &hotKeyEvent)
    if hotKeyDispatchStatus == noErr, let hotKeyEvent {
        hotKeyDispatchStatus = SetEventParameter(hotKeyEvent,
                                                 EventParamName(kEventParamDirectObject),
                                                 EventParamType(typeEventHotKeyID),
                                                 MemoryLayout<EventHotKeyID>.size,
                                                 &dispatchID)
        if hotKeyDispatchStatus == noErr {
            hotKeyDispatchStatus = SendEventToEventTarget(hotKeyEvent, GetApplicationEventTarget())
        }
    }
}
if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
if let hotKeyHandlerRef { RemoveEventHandler(hotKeyHandlerRef) }

final class WindowLifecycleProbeDelegate: NSObject, NSWindowDelegate {
    private(set) var didHandleClose = false

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            window?.contentViewController = nil
            self?.didHandleClose = true
        }
    }
}

let windowLifecycleDelegate = WindowLifecycleProbeDelegate()
let lifecycleWindow = NSWindow(contentViewController: NSViewController())
lifecycleWindow.isReleasedWhenClosed = false
lifecycleWindow.delegate = windowLifecycleDelegate
lifecycleWindow.close()
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
guard windowLifecycleDelegate.didHandleClose,
      lifecycleWindow.contentViewController == nil else {
    fputs("error: reusable window content was not released after close\n", stderr)
    exit(1)
}

print("Pasteboard roundtrip: ok")
print("Pasteboard restore snapshot items: \(snapshot.count)")
print("Accessibility trusted: \(accessibilityTrusted ? "yes" : "no")")
print("Screen recording granted: \(screenRecordingGranted ? "yes" : "no")")
print("Hotkey register probe: \(hotKeyStatus == noErr ? "ok" : "failed(\(hotKeyStatus))")")
print("Hotkey handler install: \(handlerStatus == noErr ? "ok" : "failed(\(handlerStatus))")")
print("Hotkey handler dispatch probe: \(hotKeyTriggered.pointee ? "ok" : "failed(\(hotKeyDispatchStatus))")")
print("Reusable window content release: ok")
if hotKeyStatus != noErr {
    fputs("error: hotkey register probe failed with status \(hotKeyStatus)\n", stderr)
    exit(1)
}
if handlerStatus != noErr {
    fputs("error: hotkey handler install failed with status \(handlerStatus)\n", stderr)
    exit(1)
}
if hotKeyDispatchStatus != noErr || !hotKeyTriggered.pointee {
    fputs("error: hotkey handler dispatch probe failed with status \(hotKeyDispatchStatus)\n", stderr)
    exit(1)
}
SWIFT

swift "$SWIFT_FILE"

echo ""
echo "macOS smoke checks completed."
