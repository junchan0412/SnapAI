import SwiftUI
import Carbon.HIToolbox

/// 一个可录制快捷键的控件:点击后按下组合键即可捕获。
struct HotKeyRecorder: NSViewRepresentable {
    @Binding var combo: HotKeyCombo

    func makeNSView(context: Context) -> RecorderButton {
        let v = RecorderButton()
        v.onCapture = { combo = $0 }
        v.combo = combo
        return v
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.combo = combo
        nsView.refreshTitle()
    }

    final class RecorderButton: NSButton {
        var combo: HotKeyCombo = .askDefault
        var onCapture: ((HotKeyCombo) -> Void)?
        private var recording = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            configure()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configure()
        }

        private func configure() {
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(startRecording)
            refreshTitle()
        }

        func refreshTitle() {
            title = recording ? "请按下快捷键…" : combo.displayString
        }

        @objc private func startRecording() {
            recording = true
            refreshTitle()
            window?.makeFirstResponder(self)
        }

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == UInt16(kVK_Escape) {
                recording = false
                refreshTitle()
                return
            }
            if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
                let empty = HotKeyCombo.unset
                combo = empty
                recording = false
                refreshTitle()
                onCapture?(empty)
                return
            }
            var mods: UInt32 = 0
            let flags = event.modifierFlags
            if flags.contains(.command) { mods |= UInt32(cmdKey) }
            if flags.contains(.option) { mods |= UInt32(optionKey) }
            if flags.contains(.control) { mods |= UInt32(controlKey) }
            if flags.contains(.shift) { mods |= UInt32(shiftKey) }

            // 要求至少一个修饰键,避免误触
            if mods == 0 { return }

            let newCombo = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
            combo = newCombo
            recording = false
            refreshTitle()
            onCapture?(newCombo)
        }

        override func flagsChanged(with event: NSEvent) {
            super.flagsChanged(with: event)
        }
    }
}
