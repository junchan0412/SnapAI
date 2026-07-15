import SwiftUI
import AppKit
import Carbon.HIToolbox

/// 一个可录制快捷键的控件:点击后按下组合键即可捕获。
///
/// 重构要点(反馈不清晰 / 可发现性差):
/// - 录制态用脉动高亮边框 + 实时占位文案取代仅变色的高亮,状态一目了然。
/// - `flagsChanged` 实时显示已按下的修饰键(如「⌘⌥…」),用户能确认组合进度。
/// - 仅按普通键被拒绝时,控件直接显示「需含 ⌘/⌥/⌃/⇧」原因,而非只剩一声 beep。
/// - 录制态尾部常驻「Esc 取消 · ⌫ 清除」提示,让隐藏的 Delete 清除可被发现。
/// - 成功捕获 / 清除后短暂显示 ✓ / 已清除,给出明确的结果反馈。
struct HotKeyRecorder: NSViewRepresentable {
    @Binding var combo: HotKeyCombo

    func makeNSView(context: Context) -> RecorderButton {
        let v = RecorderButton()
        v.onCapture = { combo = $0 }
        v.combo = combo
        return v
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        // 仅在外部值变化时同步,避免覆盖进行中的瞬时反馈状态。
        if nsView.combo != combo {
            nsView.combo = combo
        }
        nsView.refreshIfNeeded()
    }

    final class RecorderButton: NSButton {
        var combo: HotKeyCombo = .askDefault
        var onCapture: ((HotKeyCombo) -> Void)?
        private var recording = false

        /// 瞬时反馈状态(成功/清除/拒绝),到期后回到 idle。
        private enum FlashState { case idle, beep, success, cleared }
        private var flash: FlashState = .idle
        private var flashWork: DispatchWorkItem?

        /// 录制时实时跟踪已按下的修饰键,用于在标题中反馈组合进度。
        private var liveModifiers: NSEvent.ModifierFlags = []

        /// 录制态脉动高亮层。
        private var pulseLayer: CAShapeLayer?

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
            image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "快捷键")
            imagePosition = .imageLeading
            target = self
            action = #selector(startRecording)
            wantsLayer = true
            refreshTitle()
        }

        func refreshIfNeeded() {
            // 仅在非瞬时反馈态时刷新,避免打断成功/清除/拒绝的短暂提示。
            guard flash == .idle, !recording else { return }
            refreshTitle()
        }

        func refreshTitle() {
            switch flash {
            case .beep:
                title = HotKeyRecorderText.beepTitle
                toolTip = HotKeyRecorderText.recordingHelp
                contentTintColor = .systemRed
            case .success:
                title = "\(HotKeyRecorderText.successPrefix) \(combo.displayString)"
                toolTip = HotKeyRecorderText.help(for: combo, recording: false)
                contentTintColor = .systemGreen
            case .cleared:
                title = HotKeyRecorderText.clearedTitle
                toolTip = HotKeyRecorderText.help(for: .unset, recording: false)
                contentTintColor = .secondaryLabelColor
            case .idle:
                if recording {
                    let live = HotKeyRecorderText.liveModifierDescription(liveModifiers)
                    let head = live.isEmpty ? HotKeyRecorderText.recordingPlaceholder : "\(live)…"
                    title = "\(head)  \(HotKeyRecorderText.recordingHint)"
                    toolTip = HotKeyRecorderText.recordingHelp
                    contentTintColor = .controlAccentColor
                } else {
                    title = HotKeyRecorderText.title(for: combo, recording: false)
                    toolTip = HotKeyRecorderText.help(for: combo, recording: false)
                    contentTintColor = nil
                }
            }
            needsDisplay = true
        }

        @objc private func startRecording() {
            recording = true
            liveModifiers = NSEvent.modifierFlags
                .intersection([.command, .option, .control, .shift])
            cancelFlash()
            installPulse()
            refreshTitle()
            window?.makeFirstResponder(self)
        }

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == UInt16(kVK_Escape) {
                cancelRecording()
                return
            }
            if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
                clearCombo()
                return
            }
            var mods: UInt32 = 0
            let flags = event.modifierFlags
            if flags.contains(.command) { mods |= UInt32(cmdKey) }
            if flags.contains(.option) { mods |= UInt32(optionKey) }
            if flags.contains(.control) { mods |= UInt32(controlKey) }
            if flags.contains(.shift) { mods |= UInt32(shiftKey) }

            // 要求至少一个修饰键,避免误触;拒绝时给出可见原因而非只剩 beep。
            guard mods != 0 else {
                flashBeep()
                return
            }

            let newCombo = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
            combo = newCombo
            recording = false
            liveModifiers = []
            removePulse()
            flashSuccess()
            onCapture?(newCombo)
        }

        override func flagsChanged(with event: NSEvent) {
            super.flagsChanged(with: event)
            guard recording else { return }
            liveModifiers = event.modifierFlags
                .intersection([.command, .option, .control, .shift])
            refreshTitle()
        }

        // 失去焦点时自动退出录制,避免停留在录制态。
        override func resignFirstResponder() -> Bool {
            if recording { cancelRecording() }
            return super.resignFirstResponder()
        }

        override func layout() {
            super.layout()
            updatePulsePath()
        }

        // MARK: - 录制态控制

        private func cancelRecording() {
            recording = false
            liveModifiers = []
            removePulse()
            cancelFlash()
            refreshTitle()
        }

        private func clearCombo() {
            let empty = HotKeyCombo.unset
            combo = empty
            recording = false
            liveModifiers = []
            removePulse()
            cancelFlash()
            flashCleared()
            onCapture?(empty)
        }

        // MARK: - 瞬时反馈

        private func flashBeep() {
            NSSound.beep()
            flash = .beep
            refreshTitle()
            scheduleFlashReset(after: 1.8)
        }

        private func flashSuccess() {
            flash = .success
            refreshTitle()
            scheduleFlashReset(after: 1.1)
        }

        private func flashCleared() {
            flash = .cleared
            refreshTitle()
            scheduleFlashReset(after: 0.9)
        }

        private func scheduleFlashReset(after delay: Double) {
            flashWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.flash = .idle
                self.refreshTitle()
            }
            flashWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        private func cancelFlash() {
            flashWork?.cancel()
            flashWork = nil
            flash = .idle
        }

        // MARK: - 脉动高亮层

        private func installPulse() {
            guard pulseLayer == nil else { return }
            let pulse = CAShapeLayer()
            pulse.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
            pulse.strokeColor = NSColor.controlAccentColor.cgColor
            pulse.lineWidth = 1.5
            pulse.opacity = 0
            layer?.addSublayer(pulse)
            pulseLayer = pulse
            updatePulsePath()

            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 0.45
            anim.toValue = 1.0
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.duration = 0.7
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.add(anim, forKey: "hotkeyPulse")
        }

        private func updatePulsePath() {
            guard let pulse = pulseLayer else { return }
            let inset: CGFloat = 2
            let rect = bounds.insetBy(dx: inset, dy: inset)
            pulse.path = CGPath(roundedRect: rect,
                                cornerWidth: 6,
                                cornerHeight: 6,
                                transform: nil)
        }

        private func removePulse() {
            pulseLayer?.removeFromSuperlayer()
            pulseLayer = nil
        }
    }
}
