import AppKit
import SwiftUI

/// 一个无标题栏、可成为 key、可调整大小、点击外部自动关闭的浮动面板。
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        minSize = NSSize(width: 320, height: 200)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
    }

    // 允许无标题面板成为 key，从而能接收键盘输入(追问框)
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 管理浮动结果窗口的显示/隐藏与定位
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private let vm: ResultViewModel
    private let settings: AppSettings
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(vm: ResultViewModel) {
        self.vm = vm
        self.settings = vm.settings
        super.init()
    }

    /// 在鼠标位置附近显示面板
    func show() {
        let rootView = ResultView(vm: vm, onClose: { [weak self] in self?.hide() })
        let hosting = NSHostingView(rootView: rootView)

        let panel: FloatingPanel
        if let existing = self.panel {
            panel = existing
            panel.contentView = hosting
        } else {
            let w = max(320, settings.panelWidth)
            let h = max(200, settings.panelHeight)
            panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h))
            panel.contentView = hosting
            panel.delegate = self
            self.panel = panel
        }

        positionNearCursor(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installDismissMonitors()
    }

    func hide() {
        vm.cancel()
        panel?.orderOut(nil)
        removeDismissMonitors()
    }

    /// 窗口尺寸变化时记忆(#8)
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel = panel else { return }
        settings.panelWidth = panel.frame.width
        settings.panelHeight = panel.frame.height
        settings.save()
    }

    private func positionNearCursor(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            panel.center(); return
        }
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)
        let vf = screen.visibleFrame
        // 防止超出屏幕边界
        if origin.x + size.width > vf.maxX { origin.x = vf.maxX - size.width - 8 }
        if origin.x < vf.minX { origin.x = vf.minX + 8 }
        if origin.y < vf.minY { origin.y = mouse.y + 12 }
        if origin.y + size.height > vf.maxY { origin.y = vf.maxY - size.height - 8 }
        panel.setFrameOrigin(origin)
    }

    // 点击面板外部 / 按 Esc 时关闭(固定状态下不关闭)
    private func installDismissMonitors() {
        removeDismissMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, !self.vm.isPinned else { return }
            self.hide()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 { // esc
                if self.vm.isPinned {
                    self.vm.isPinned = false
                } else {
                    self.hide()
                }
                return nil
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }
}
