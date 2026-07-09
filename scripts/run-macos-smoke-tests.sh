#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

step() {
  echo ""
  echo "==> $1"
}

step "检查逻辑 target 边界"
scripts/check-logic-symlinks.sh

step "运行逻辑测试"
scripts/run-logic-tests.sh

step "探测 macOS 剪贴板与隐私权限"
SWIFT_FILE=$(mktemp "${TMPDIR:-/tmp}/snapai-macos-smoke.XXXXXX.swift")
trap 'rm -f "$SWIFT_FILE"' EXIT

cat > "$SWIFT_FILE" <<'SWIFT'
import AppKit
import ApplicationServices
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
print("Pasteboard roundtrip: ok")
print("Pasteboard restore snapshot items: \(snapshot.count)")
print("Accessibility trusted: \(accessibilityTrusted ? "yes" : "no")")
print("Screen recording granted: \(screenRecordingGranted ? "yes" : "no")")
SWIFT

swift "$SWIFT_FILE"

echo ""
echo "macOS smoke checks completed."
